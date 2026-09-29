"""Background poller: Icecast admin → luisterlog + snapshots per mount."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select

from app.config import get_settings
from app.db import SessionLocal
from app.icecast_admin import IcecastListener, fetch_mount_stats
from app.models import ListenerSession, ListenerSnapshot, Mount, MountStatsRollup, utcnow

logger = logging.getLogger("bh.stats")

# In-memory: mount -> client_id -> open ListenerSession.id
_active: dict[str, dict[str, int]] = {}
_last_snapshot_at: datetime | None = None
_task: asyncio.Task | None = None


def _aware(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def _connected_at(listener: IcecastListener, now: datetime) -> datetime:
    secs = max(0, listener.connected_seconds)
    return now - timedelta(seconds=secs)


def _get_or_create_rollup(db, mount_name: str) -> MountStatsRollup:
    rollup = db.get(MountStatsRollup, mount_name)
    if rollup is None:
        rollup = MountStatsRollup(mount_name=mount_name)
        db.add(rollup)
        db.flush()
    return rollup


def _close_session(db, session: ListenerSession, ended_at: datetime) -> None:
    if session.disconnected_at is not None:
        return
    started = _aware(session.connected_at)
    duration = max(0, int((ended_at - started).total_seconds()))
    session.disconnected_at = ended_at
    session.duration_seconds = duration

    rollup = _get_or_create_rollup(db, session.mount_name)
    rollup.total_sessions = (rollup.total_sessions or 0) + 1
    rollup.total_listen_seconds = float(rollup.total_listen_seconds or 0) + duration
    rollup.updated_at = ended_at


def poll_once() -> None:
    settings = get_settings()
    now = utcnow()
    live = fetch_mount_stats()

    db = SessionLocal()
    try:
        known_mounts = set(db.scalars(select(Mount.name)).all())
        # Also track mounts that Icecast still reports (source online)
        mounts_to_process = known_mounts | set(live.keys())

        for mount_name in mounts_to_process:
            stats = live.get(mount_name)
            listeners = stats.listeners_detail if stats else []
            by_id = {lis.client_id: lis for lis in listeners}
            active_map = _active.setdefault(mount_name, {})

            # New / still-active listeners
            for client_id, lis in by_id.items():
                if client_id in active_map:
                    continue
                session = ListenerSession(
                    mount_name=mount_name,
                    client_id=client_id,
                    ip=lis.ip,
                    user_agent=lis.user_agent,
                    connected_at=_connected_at(lis, now),
                )
                db.add(session)
                db.flush()
                active_map[client_id] = session.id

            # Disconnected listeners
            for client_id in list(active_map.keys()):
                if client_id in by_id:
                    continue
                session = db.get(ListenerSession, active_map[client_id])
                if session is not None:
                    _close_session(db, session, now)
                del active_map[client_id]

            # Rollup peak + optional snapshot
            current_count = stats.listeners if stats else 0
            icecast_peak = stats.listener_peak if stats else 0
            rollup = _get_or_create_rollup(db, mount_name)
            peak_candidate = max(current_count, icecast_peak, rollup.peak_listeners or 0)
            if peak_candidate > (rollup.peak_listeners or 0):
                rollup.peak_listeners = peak_candidate
                rollup.peak_at = now
            rollup.updated_at = now

        global _last_snapshot_at
        should_snapshot = (
            _last_snapshot_at is None
            or (now - _last_snapshot_at).total_seconds() >= settings.stats_snapshot_seconds
        )
        if should_snapshot:
            for mount_name in mounts_to_process:
                stats = live.get(mount_name)
                db.add(
                    ListenerSnapshot(
                        mount_name=mount_name,
                        recorded_at=now,
                        listeners=stats.listeners if stats else 0,
                        listener_peak=stats.listener_peak if stats else 0,
                        bitrate=stats.bitrate if stats else None,
                        source_connected=stats is not None,
                    )
                )
            _last_snapshot_at = now
            _prune_old(db, now, settings.stats_retention_days)

        db.commit()
    except Exception:
        db.rollback()
        logger.exception("stats poll failed")
    finally:
        db.close()


def _prune_old(db, now: datetime, retention_days: int) -> None:
    if retention_days <= 0:
        return
    cutoff = now - timedelta(days=retention_days)
    db.execute(delete(ListenerSnapshot).where(ListenerSnapshot.recorded_at < cutoff))
    db.execute(
        delete(ListenerSession).where(
            ListenerSession.disconnected_at.is_not(None),
            ListenerSession.disconnected_at < cutoff,
        )
    )


async def _loop() -> None:
    settings = get_settings()
    interval = max(5, settings.stats_poll_seconds)
    # Small delay so Icecast can come up with the API
    await asyncio.sleep(2)
    while True:
        try:
            await asyncio.to_thread(poll_once)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("stats loop error")
        await asyncio.sleep(interval)


def start_stats_collector() -> None:
    global _task
    if not get_settings().stats_enabled:
        logger.info("stats collector disabled")
        return
    if _task is not None and not _task.done():
        return
    _task = asyncio.create_task(_loop(), name="bh-stats-collector")
    logger.info("stats collector started")


async def stop_stats_collector() -> None:
    global _task
    if _task is None:
        return
    _task.cancel()
    try:
        await _task
    except asyncio.CancelledError:
        pass
    _task = None
