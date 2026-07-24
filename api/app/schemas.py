from pydantic import BaseModel, ConfigDict, Field, model_validator


class MountCreate(BaseModel):
    """Create a mountpoint. Pass the name as `name`, `mountpoint`, or `mount`."""

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {"name": "studio-1", "title": "Studio 1"},
                {"mountpoint": "live", "password": "my-secret-password"},
                {"mount": "event-hall-a"},
            ]
        }
    )

    name: str | None = Field(
        default=None,
        min_length=1,
        max_length=64,
        description="Mountpoint name without leading slash (e.g. live → /live). Alias: mountpoint, mount.",
        examples=["live", "studio-1"],
    )
    mountpoint: str | None = Field(
        default=None,
        min_length=1,
        max_length=64,
        description="Alias for name.",
        examples=["live"],
    )
    mount: str | None = Field(
        default=None,
        min_length=1,
        max_length=64,
        description="Alias for name.",
        examples=["live"],
    )
    password: str | None = Field(
        default=None,
        min_length=8,
        max_length=128,
        description="Source (encoder) password. Auto-generated if omitted.",
    )
    title: str | None = Field(default=None, max_length=255)
    description: str | None = None
    enabled: bool = True

    @model_validator(mode="after")
    def require_mount_name(self) -> "MountCreate":
        resolved = self.name or self.mountpoint or self.mount
        if not resolved:
            raise ValueError("Provide name, mountpoint, or mount")
        self.name = resolved
        return self


class MountUpdate(BaseModel):
    password: str | None = Field(default=None, min_length=8, max_length=128)
    title: str | None = Field(default=None, max_length=255)
    description: str | None = None
    enabled: bool | None = None


class MountOut(BaseModel):
    name: str = Field(description="Normalized mount path, always starts with /")
    mountpoint: str = Field(description="Same as name (convenience for integrators)")
    title: str | None
    description: str | None
    enabled: bool
    listen_url: str = Field(description="Public HTTPS URL for listeners")
    source_url: str = Field(description="Base URL encoders should use (host)")
    source_mount: str = Field(description="Mount path for the encoder, e.g. /live")
    source_port_http: int = Field(default=8000, description="Encoder port (Icecast direct)")
    source_port_https: int = Field(default=8000, description="Same as HTTP — encode on 8000, listen on 443")
    created_at: str
    updated_at: str


class MountCreated(MountOut):
    password: str = Field(description="Source password (returned only on create/rotate)")


class HealthOut(BaseModel):
    status: str
    service: str
