from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BH_", env_file=".env", extra="ignore")

    api_token: str = "change-me"
    database_url: str = "sqlite:///./data/bh-icecast.db"
    data_dir: str = "./data"
    public_listen_base: str = "http://localhost:8000"
    mount_name_max_length: int = 64
    # Per-mount statistics / luisterlog
    stats_enabled: bool = True
    stats_poll_seconds: int = 15
    stats_snapshot_seconds: int = 60
    stats_retention_days: int = 90


@lru_cache
def get_settings() -> Settings:
    return Settings()
