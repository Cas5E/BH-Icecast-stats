from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.icecast_admin import fetch_mount_stats
from app.models import ListenerSession, ListenerSnapshot, Mount, MountStatsRollup
from app.schemas import (
    ListenerLogOut,
    ListenerSessionOut,
    LiveListenerOut,
    MountStatsOut,
    SnapshotOut,
    StatsOverviewOut,
)
from app.security import normalize_mount_name, require_api_token

router = APIRouter(
    prefix="/api/v1",
    tags=["stats"],
    dependencies=[Depends(require_api_token)],
)


def _iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def _session_out(row: ListenerSession) -> ListenerSessionOut:
    return ListenerSessionOut(
        id=row.id,
        mount_name=row.mount_name,
        client_id=row.client_id,
        ip=row.ip,
        user_agent=row.user_agent,
        connected_at=_iso(row.connected_at) or "",
        disconnected_at=_iso(row.disconnected_at),
        duration_seconds=row.duration_seconds,
        active=row.disconnected_at is None,
    )


def _build_mount_stats(
    mount_name: str,
    mount: Mount | None,
    rollup: MountStatsRollup | None,
    live_map: dict,
    active_count: int,
) -> MountStatsOut:
    live = live_map.get(mount_name)
    peak = 0
    peak_at = None
    total_sessions = 0
    total_secs = 0.0
    if rollup:
        peak = rollup.peak_listeners or 0
        peak_at = rollup.peak_at
        total_sessions = rollup.total_sessions or 0
        total_secs = float(rollup.total_listen_seconds or 0)

    current = live.listeners if live else 0
    if live:
        peak = max(peak, live.listener_peak, current)

    live_listeners: list[LiveListenerOut] = []
    if live:
        now = datetime.now(timezone.utc)
        for lis in live.listeners_detail:
            connected_at = now - timedelta(seconds=max(0, lis.connected_seconds))
            live_listeners.append(
                LiveListenerOut(
                    client_id=lis.client_id,
                    ip=lis.ip,
                    user_agent=lis.user_agent,
                    connected_seconds=lis.connected_seconds,
                    connected_at=connected_at.isoformat(),
                )
            )

    return MountStatsOut(
        mount_name=mount_name,
        title=mount.title if mount else (live.server_name if live else None),
        source_connected=live is not None,
        listeners_current=current,
        listeners_peak=peak,
        listeners_peak_at=_iso(peak_at),
        bitrate=live.bitrate if live else None,
        genre=live.genre if live else None,
        server_name=live.server_name if live else None,
        stream_start=live.stream_start if live else None,
        total_sessions=total_sessions,
        total_listen_seconds=total_secs,
        total_listen_hours=round(total_secs / 3600.0, 3),
        active_sessions=active_count,
        live_listeners=live_listeners,
    )


@router.get("/stats", response_model=StatsOverviewOut, summary="Stats overview alle mounts")
def stats_overview(db: Session = Depends(get_db)) -> StatsOverviewOut:
    mounts = db.scalars(select(Mount).order_by(Mount.name)).all()
    live_map = fetch_mount_stats()
    rollups = {r.mount_name: r for r in db.scalars(select(MountStatsRollup)).all()}

    active_rows = db.execute(
        select(ListenerSession.mount_name, func.count())
        .where(ListenerSession.disconnected_at.is_(None))
        .group_by(ListenerSession.mount_name)
    ).all()
    active_by_mount = {name: count for name, count in active_rows}

    items: list[MountStatsOut] = []
    seen: set[str] = set()
    for mount in mounts:
        seen.add(mount.name)
        items.append(
            _build_mount_stats(
                mount.name,
                mount,
                rollups.get(mount.name),
                live_map,
                active_by_mount.get(mount.name, 0),
            )
        )
    # Icecast-only mounts (not in DB) still show up while live
    for mount_name in sorted(live_map.keys()):
        if mount_name in seen:
            continue
        items.append(
            _build_mount_stats(
                mount_name,
                None,
                rollups.get(mount_name),
                live_map,
                active_by_mount.get(mount_name, 0),
            )
        )

    return StatsOverviewOut(
        mounts=items,
        listeners_total=sum(m.listeners_current for m in items),
        sources_connected=sum(1 for m in items if m.source_connected),
    )


@router.get(
    "/mounts/{mount_name}/stats",
    response_model=MountStatsOut,
    summary="Statistieken voor één mountpoint",
)
def mount_stats(mount_name: str, db: Session = Depends(get_db)) -> MountStatsOut:
    name = normalize_mount_name(mount_name)
    mount = db.get(Mount, name)
    if mount is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")

    live_map = fetch_mount_stats()
    rollup = db.get(MountStatsRollup, name)
    active_count = db.scalar(
        select(func.count())
        .select_from(ListenerSession)
        .where(
            ListenerSession.mount_name == name,
            ListenerSession.disconnected_at.is_(None),
        )
    ) or 0
    return _build_mount_stats(name, mount, rollup, live_map, int(active_count))


@router.get(
    "/mounts/{mount_name}/listeners",
    response_model=list[LiveListenerOut],
    summary="Actieve luisteraars (live)",
)
def mount_listeners(mount_name: str, db: Session = Depends(get_db)) -> list[LiveListenerOut]:
    name = normalize_mount_name(mount_name)
    if db.get(Mount, name) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")
    stats = _build_mount_stats(name, None, None, fetch_mount_stats(), 0)
    return stats.live_listeners


@router.get(
    "/mounts/{mount_name}/listener-log",
    response_model=ListenerLogOut,
    summary="Luisterlog (historische sessies)",
)
def listener_log(
    mount_name: str,
    db: Session = Depends(get_db),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    active: bool | None = Query(
        default=None,
        description="Filter: true = alleen actief, false = alleen afgesloten",
    ),
) -> ListenerLogOut:
    name = normalize_mount_name(mount_name)
    if db.get(Mount, name) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")

    filters = [ListenerSession.mount_name == name]
    if active is True:
        filters.append(ListenerSession.disconnected_at.is_(None))
    elif active is False:
        filters.append(ListenerSession.disconnected_at.is_not(None))

    total = db.scalar(
        select(func.count()).select_from(ListenerSession).where(*filters)
    ) or 0
    rows = db.scalars(
        select(ListenerSession)
        .where(*filters)
        .order_by(ListenerSession.connected_at.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    return ListenerLogOut(
        total=int(total),
        limit=limit,
        offset=offset,
        items=[_session_out(r) for r in rows],
    )


@router.get(
    "/mounts/{mount_name}/stats/history",
    response_model=list[SnapshotOut],
    summary="Listener-historiek (snapshots)",
)
def stats_history(
    mount_name: str,
    db: Session = Depends(get_db),
    hours: int = Query(default=24, ge=1, le=24 * 90),
) -> list[SnapshotOut]:
    name = normalize_mount_name(mount_name)
    if db.get(Mount, name) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")

    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    rows = db.scalars(
        select(ListenerSnapshot)
        .where(
            ListenerSnapshot.mount_name == name,
            ListenerSnapshot.recorded_at >= since,
        )
        .order_by(ListenerSnapshot.recorded_at.asc())
    ).all()
    return [
        SnapshotOut(
            recorded_at=_iso(r.recorded_at) or "",
            listeners=r.listeners,
            listener_peak=r.listener_peak,
            bitrate=r.bitrate,
            source_connected=r.source_connected,
        )
        for r in rows
    ]
