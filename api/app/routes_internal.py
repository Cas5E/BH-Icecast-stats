from fastapi import APIRouter, Depends, Header, Response, status
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Mount
from app.security import mount_from_uri, parse_basic_password, verify_password

router = APIRouter(prefix="/internal", tags=["internal"])


@router.get("/source-auth")
def source_auth(
    response: Response,
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None),
    x_original_uri: str | None = Header(default=None, alias="X-Original-URI"),
    x_original_method: str | None = Header(default=None, alias="X-Original-Method"),
) -> Response:
    """
    nginx auth_request endpoint.
    Validates per-mount source password without touching Icecast config.
    """
    method = (x_original_method or "").upper()
    if method in {"GET", "HEAD"}:
        return Response(status_code=status.HTTP_200_OK)

    mount_name = mount_from_uri(x_original_uri or "")
    password = parse_basic_password(authorization)

    if not mount_name or password is None:
        return Response(status_code=status.HTTP_401_UNAUTHORIZED)

    mount = db.get(Mount, mount_name)
    if mount is None or not mount.enabled:
        return Response(status_code=status.HTTP_403_FORBIDDEN)

    if not verify_password(password, mount.password_hash):
        return Response(status_code=status.HTTP_403_FORBIDDEN)

    response.status_code = status.HTTP_200_OK
    response.headers["X-BH-Mount"] = mount_name
    return response
