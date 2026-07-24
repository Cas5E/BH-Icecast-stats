from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.db import SessionLocal, init_db
from app.icecast_sync import sync_mounts_to_icecast
from app.routes_internal import router as internal_router
from app.routes_mounts import router as mounts_router
from app.schemas import HealthOut

settings = get_settings()
Path(settings.data_dir).mkdir(parents=True, exist_ok=True)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    db = SessionLocal()
    try:
        sync_mounts_to_icecast(db)
    finally:
        db.close()
    yield


app = FastAPI(
    title="BH-Icecast API",
    description=(
        "Manage Icecast mountpoints with per-mount source passwords.\n\n"
        "Create mounts with a custom name via `name`, `mountpoint`, or `mount` "
        "in the JSON body, or use `PUT /api/v1/mounts/{name}`.\n\n"
        "Human docs: see repository `docs/API.md`."
    ),
    version="1.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(mounts_router)
app.include_router(internal_router)


@app.get("/health", response_model=HealthOut, tags=["system"])
def health() -> HealthOut:
    return HealthOut(status="ok", service="bh-icecast-api")
