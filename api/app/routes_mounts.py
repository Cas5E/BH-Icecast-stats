from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.db import get_db
from app.icecast_admin import kick_source
from app.icecast_sync import sync_mounts_to_icecast
from app.models import Mount, utcnow
from app.schemas import MountCreate, MountCreated, MountOut, MountUpdate
from app.security import (
    generate_password,
    hash_password,
    normalize_mount_name,
    require_api_token,
)

router = APIRouter(
    prefix="/api/v1/mounts",
    tags=["mounts"],
    dependencies=[Depends(require_api_token)],
)


def _to_out(mount: Mount, settings: Settings) -> MountOut:
    base = settings.public_listen_base.rstrip("/")
    host = base.replace("https://", "").replace("http://", "")
    return MountOut(
        name=mount.name,
        mountpoint=mount.name,
        title=mount.title,
        description=mount.description,
        enabled=mount.enabled,
        listen_url=f"{base}{mount.name}",
        source_url=host,
        source_mount=mount.name,
        # Encoders must use Icecast directly — nginx SOURCE proxy drops ~20s
        source_port_http=8000,
        source_port_https=8000,
        created_at=mount.created_at.isoformat(),
        updated_at=mount.updated_at.isoformat(),
    )


def _create(name: str, body: MountCreate, db: Session, settings: Settings) -> MountCreated:
    name = normalize_mount_name(name)
    if db.get(Mount, name) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Mount already exists")

    password = body.password or generate_password()
    mount = Mount(
        name=name,
        password_hash=hash_password(password),
        password_plain=password,
        title=body.title,
        description=body.description,
        enabled=body.enabled,
    )
    db.add(mount)
    db.commit()
    db.refresh(mount)
    sync_mounts_to_icecast(db)
    out = _to_out(mount, settings)
    return MountCreated(**out.model_dump(), password=password)


@router.get("", response_model=list[MountOut], summary="List mountpoints")
def list_mounts(
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> list[MountOut]:
    mounts = db.scalars(select(Mount).order_by(Mount.name)).all()
    return [_to_out(m, settings) for m in mounts]


@router.post(
    "",
    response_model=MountCreated,
    status_code=status.HTTP_201_CREATED,
    summary="Create mountpoint (name in body)",
)
def create_mount(
    body: MountCreate,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MountCreated:
    assert body.name is not None
    return _create(body.name, body, db, settings)


@router.put(
    "/{mount_name:path}",
    response_model=MountCreated,
    status_code=status.HTTP_201_CREATED,
    summary="Create mountpoint (name in URL)",
)
def put_mount(
    mount_name: str,
    body: MountUpdate | None = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MountCreated:
    body = body or MountUpdate()
    create = MountCreate(
        name=mount_name,
        password=body.password,
        title=body.title,
        description=body.description,
        enabled=True if body.enabled is None else body.enabled,
    )
    return _create(mount_name, create, db, settings)


@router.get("/{mount_name:path}", response_model=MountOut, summary="Get mountpoint")
def get_mount(
    mount_name: str,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MountOut:
    name = normalize_mount_name(mount_name)
    mount = db.get(Mount, name)
    if mount is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")
    return _to_out(mount, settings)


@router.patch("/{mount_name:path}", response_model=MountCreated | MountOut, summary="Update mountpoint")
def update_mount(
    mount_name: str,
    body: MountUpdate,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MountCreated | MountOut:
    name = normalize_mount_name(mount_name)
    mount = db.get(Mount, name)
    if mount is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")

    new_password: str | None = None
    if body.password is not None:
        new_password = body.password
        mount.password_hash = hash_password(body.password)
        mount.password_plain = body.password
    if body.title is not None:
        mount.title = body.title
    if body.description is not None:
        mount.description = body.description
    if body.enabled is not None:
        mount.enabled = body.enabled
    mount.updated_at = utcnow()

    db.commit()
    db.refresh(mount)
    sync_mounts_to_icecast(db)

    if body.enabled is False or new_password is not None:
        kick_source(name)

    out = _to_out(mount, settings)
    if new_password is not None:
        return MountCreated(**out.model_dump(), password=new_password)
    return out


@router.post("/{mount_name:path}/rotate-password", response_model=MountCreated, summary="Rotate source password")
def rotate_password(
    mount_name: str,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MountCreated:
    name = normalize_mount_name(mount_name)
    mount = db.get(Mount, name)
    if mount is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")

    password = generate_password()
    mount.password_hash = hash_password(password)
    mount.password_plain = password
    mount.updated_at = utcnow()
    db.commit()
    db.refresh(mount)
    sync_mounts_to_icecast(db)
    kick_source(name)

    out = _to_out(mount, settings)
    return MountCreated(**out.model_dump(), password=password)


@router.delete("/{mount_name:path}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete mountpoint")
def delete_mount(
    mount_name: str,
    db: Session = Depends(get_db),
) -> None:
    name = normalize_mount_name(mount_name)
    mount = db.get(Mount, name)
    if mount is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mount not found")
    db.delete(mount)
    db.commit()
    sync_mounts_to_icecast(db)
    kick_source(name)
