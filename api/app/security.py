import re
import secrets
from urllib.parse import unquote

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from passlib.context import CryptContext

from app.config import Settings, get_settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)

MOUNT_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$")


def normalize_mount_name(name: str) -> str:
    cleaned = name.strip().lstrip("/")
    if not cleaned or not MOUNT_RE.match(cleaned):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid mount name. Use 1-63 chars: letters, digits, . _ -",
        )
    return f"/{cleaned}"


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def generate_password(length: int = 24) -> str:
    # Avoid ambiguous characters for manual entry in encoders
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def require_api_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    settings: Settings = Depends(get_settings),
) -> None:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    if not secrets.compare_digest(credentials.credentials, settings.api_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API token")


def parse_basic_password(authorization: str | None) -> str | None:
    """Extract password from HTTP Basic auth (Icecast source clients)."""
    if not authorization or not authorization.lower().startswith("basic "):
        return None
    import base64

    try:
        raw = base64.b64decode(authorization.split(" ", 1)[1]).decode("utf-8")
    except Exception:
        return None
    if ":" not in raw:
        return raw or None
    _, password = raw.split(":", 1)
    return password


def mount_from_uri(uri: str) -> str | None:
    path = unquote(uri.split("?", 1)[0])
    if not path.startswith("/"):
        path = "/" + path
    # Drop trailing slash except root
    if len(path) > 1:
        path = path.rstrip("/")
    if path in {"", "/"}:
        return None
    # Ignore Icecast internal paths
    blocked_prefixes = ("/admin", "/status", "/server", "/xml", "/favicon")
    if any(path.startswith(p) for p in blocked_prefixes):
        return None
    if path.endswith((".xsl", ".css", ".js", ".gif", ".png", ".ico")):
        return None
    return path
