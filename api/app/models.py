from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Float, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Mount(Base):
    __tablename__ = "mounts"

    name: Mapped[str] = mapped_column(String(128), primary_key=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    # Plaintext needed to provision Icecast <mount><password> (API is IP-restricted).
    password_plain: Mapped[str | None] = mapped_column(Text, nullable=True)
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class ListenerSession(Base):
    """Luisterlog: één rij per luistersessie (connect → disconnect)."""

    __tablename__ = "listener_sessions"
    __table_args__ = (
        Index("ix_listener_sessions_mount_connected", "mount_name", "connected_at"),
        Index("ix_listener_sessions_mount_active", "mount_name", "disconnected_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    mount_name: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    client_id: Mapped[str] = mapped_column(String(128), nullable=False)
    ip: Mapped[str] = mapped_column(String(64), nullable=False)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)
    connected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    disconnected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)


class ListenerSnapshot(Base):
    """Periodieke sample van actieve listeners per mount (voor grafieken)."""

    __tablename__ = "listener_snapshots"
    __table_args__ = (Index("ix_listener_snapshots_mount_ts", "mount_name", "recorded_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    mount_name: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    listeners: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    listener_peak: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    bitrate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_connected: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)


class MountStatsRollup(Base):
    """Lichte aggregates per mount (peaks / totals), bijgewerkt door de collector."""

    __tablename__ = "mount_stats_rollups"

    mount_name: Mapped[str] = mapped_column(String(128), primary_key=True)
    peak_listeners: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    peak_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    total_sessions: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_listen_seconds: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
