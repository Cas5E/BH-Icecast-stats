import os
from urllib.parse import quote

import httpx


def kick_source(mount_name: str) -> None:
    """Best-effort: disconnect an active source via Icecast admin API."""
    base = os.getenv("ICECAST_ADMIN_URL", "").rstrip("/")
    user = os.getenv("ICECAST_ADMIN_USER", "admin")
    password = os.getenv("ICECAST_ADMIN_PASSWORD", "")
    if not base or not password:
        return

    url = f"{base}/admin/killsource?mount={quote(mount_name)}"
    try:
        httpx.get(url, auth=(user, password), timeout=3.0)
    except Exception:
        # Non-fatal: mount is already removed/disabled in our DB
        return
