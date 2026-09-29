import os
from dataclasses import dataclass
from urllib.parse import quote
from xml.etree import ElementTree as ET

import httpx


def _admin_auth() -> tuple[str, str, str] | None:
    base = os.getenv("ICECAST_ADMIN_URL", "").rstrip("/")
    user = os.getenv("ICECAST_ADMIN_USER", "admin")
    password = os.getenv("ICECAST_ADMIN_PASSWORD", "")
    if not base or not password:
        return None
    return base, user, password


def kick_source(mount_name: str) -> None:
    """Best-effort: disconnect an active source via Icecast admin API."""
    auth = _admin_auth()
    if auth is None:
        return
    base, user, password = auth
    url = f"{base}/admin/killsource?mount={quote(mount_name)}"
    try:
        httpx.get(url, auth=(user, password), timeout=3.0)
    except Exception:
        # Non-fatal: mount is already removed/disabled in our DB
        return


@dataclass(frozen=True)
class IcecastListener:
    client_id: str
    ip: str
    user_agent: str | None
    connected_seconds: int


@dataclass(frozen=True)
class IcecastMountStats:
    mount: str
    listeners: int
    listener_peak: int
    bitrate: int | None
    genre: str | None
    server_name: str | None
    server_description: str | None
    stream_start: str | None
    source_ip: str | None
    listeners_detail: list[IcecastListener]


def _text(el: ET.Element | None, tag: str, default: str | None = None) -> str | None:
    if el is None:
        return default
    child = el.find(tag)
    if child is None or child.text is None:
        return default
    return child.text


def _int(el: ET.Element | None, tag: str, default: int = 0) -> int:
    raw = _text(el, tag)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _parse_listeners(source_el: ET.Element) -> list[IcecastListener]:
    out: list[IcecastListener] = []
    for listener in source_el.findall("listener"):
        client_id = _text(listener, "ID") or _text(listener, "id") or ""
        ip = _text(listener, "IP") or _text(listener, "ip") or ""
        if not client_id and not ip:
            continue
        ua = _text(listener, "UserAgent") or _text(listener, "useragent")
        connected = _int(listener, "Connected")
        if not client_id:
            client_id = f"{ip}:{connected}:{ua or ''}"
        out.append(
            IcecastListener(
                client_id=client_id,
                ip=ip or "unknown",
                user_agent=ua,
                connected_seconds=connected,
            )
        )
    return out


def fetch_mount_stats() -> dict[str, IcecastMountStats]:
    """
    Fetch per-mount stats + current listeners from Icecast admin.
    Returns {} when admin is unreachable/unconfigured.
    """
    auth = _admin_auth()
    if auth is None:
        return {}
    base, user, password = auth

    try:
        stats_resp = httpx.get(f"{base}/admin/stats", auth=(user, password), timeout=5.0)
        stats_resp.raise_for_status()
    except Exception:
        return {}

    try:
        root = ET.fromstring(stats_resp.text)
    except ET.ParseError:
        return {}

    result: dict[str, IcecastMountStats] = {}
    for source in root.findall("source"):
        mount = source.attrib.get("mount") or _text(source, "mount") or ""
        if not mount:
            continue
        if not mount.startswith("/"):
            mount = f"/{mount}"

        listeners = _parse_listeners(source)
        # stats.xml often omits listener detail; enrich via listclients
        if not listeners:
            listeners = list_clients(mount)

        result[mount] = IcecastMountStats(
            mount=mount,
            listeners=_int(source, "listeners", len(listeners)),
            listener_peak=_int(source, "listener_peak"),
            bitrate=_int(source, "bitrate") or None,
            genre=_text(source, "genre"),
            server_name=_text(source, "server_name") or _text(source, "title"),
            server_description=_text(source, "server_description"),
            stream_start=_text(source, "stream_start"),
            source_ip=_text(source, "source_ip"),
            listeners_detail=listeners,
        )
    return result


def list_clients(mount_name: str) -> list[IcecastListener]:
    auth = _admin_auth()
    if auth is None:
        return []
    base, user, password = auth
    url = f"{base}/admin/listclients?mount={quote(mount_name)}"
    try:
        resp = httpx.get(url, auth=(user, password), timeout=5.0)
        resp.raise_for_status()
        root = ET.fromstring(resp.text)
    except Exception:
        return []

    # listclients may nest under <source> or return listeners at root
    source = root.find("source")
    if source is not None:
        return _parse_listeners(source)
    return _parse_listeners(root)
