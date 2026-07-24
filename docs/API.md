# BH-Icecast API Documentation

Base URL (from an allowed IP): `https://icecast.ebbersbroadcast.technology`  
Local via SSH tunnel: `http://127.0.0.1:8080` after:
```bash
ssh -L 8080:127.0.0.1:8080 root@185.249.252.114
```

Interactive docs: `/docs` (same host, **IP-restricted**)  
OpenAPI JSON: `/openapi.json`

## Access control

The management API (`/api`, `/docs`, `/redoc`, `/openapi.json`, `/health`) is **not public**.

| Access | How |
|--------|-----|
| Your PC / office | Add your public IP to `BH_API_ALLOW_IPS` in `.env`, then recreate proxy |
| Any network | SSH tunnel to `127.0.0.1:8080` on the server |
| Listeners / encoders | Unaffected — streams stay public on 80/443 |

Multiple IPs: `BH_API_ALLOW_IPS=1.2.3.4,5.6.7.8`

## Authentication

All `/api/v1/*` endpoints require a Bearer token:

```http
Authorization: Bearer <BH_API_TOKEN>
Content-Type: application/json
```

The token lives in `/opt/bh-icecast/.env` on the server (`BH_API_TOKEN`).

`/health` is public (no auth).

---

## Concepts

| Term | Meaning |
|------|---------|
| Mountpoint / mount | Stream path, e.g. `live` → `/live` |
| Source password | Password the encoder (OBS, butt, …) uses to publish |
| Listen URL | Public HTTPS URL for listeners |
| Instant apply | Create/update/delete does **not** reload Icecast; existing *other* listeners stay connected |

Mount names: `1–63` chars, start with a letter/digit, then `a-z A-Z 0-9 . _ -`. Leading `/` is optional; the API always stores `/name`.

---

## Endpoints

### `GET /health`

Liveness check.

**Response `200`**
```json
{ "status": "ok", "service": "bh-icecast-api" }
```

---

### `GET /api/v1/mounts`

List all mountpoints.

**Response `200`**
```json
[
  {
    "name": "/studio-1",
    "mountpoint": "/studio-1",
    "title": "Studio 1",
    "description": null,
    "enabled": true,
    "listen_url": "https://icecast.ebbersbroadcast.technology/studio-1",
    "source_url": "icecast.ebbersbroadcast.technology",
    "source_mount": "/studio-1",
    "source_port_http": 80,
    "source_port_https": 443,
    "created_at": "2026-07-24T12:00:00+00:00",
    "updated_at": "2026-07-24T12:00:00+00:00"
  }
]
```

---

### `POST /api/v1/mounts`

Create a mountpoint. **Pass the name in the body** as one of:

- `name`
- `mountpoint`
- `mount`

**Request**
```json
{
  "name": "studio-1",
  "password": "optional-min-8-chars",
  "title": "Studio 1",
  "description": "optional",
  "enabled": true
}
```

Equivalent:
```json
{ "mountpoint": "studio-1" }
```
```json
{ "mount": "studio-1" }
```

If `password` is omitted, one is generated.

**Response `201`** (password only returned here / on rotate)
```json
{
  "name": "/studio-1",
  "mountpoint": "/studio-1",
  "title": "Studio 1",
  "description": null,
  "enabled": true,
  "listen_url": "https://icecast.ebbersbroadcast.technology/studio-1",
  "source_url": "icecast.ebbersbroadcast.technology",
  "source_mount": "/studio-1",
  "source_port_http": 80,
  "source_port_https": 443,
  "created_at": "...",
  "updated_at": "...",
  "password": "generated-or-provided-secret"
}
```

**Errors**
| Code | When |
|------|------|
| `400` | Invalid name |
| `401` | Missing/invalid token |
| `409` | Mount already exists |
| `422` | Validation error (e.g. no name field) |

**curl**
```bash
curl -X POST https://icecast.ebbersbroadcast.technology/api/v1/mounts \
  -H "Authorization: Bearer $BH_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mountpoint":"studio-1","title":"Studio 1"}'
```

---

### `PUT /api/v1/mounts/{mount_name}`

Create with the **name in the URL** (handy for idempotent-style integrators).

```bash
curl -X PUT https://icecast.ebbersbroadcast.technology/api/v1/mounts/studio-1 \
  -H "Authorization: Bearer $BH_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Studio 1"}'
```

Body fields optional: `password`, `title`, `description`, `enabled`.  
Response: same as `POST` (`201`). Conflict `409` if it already exists.

---

### `GET /api/v1/mounts/{mount_name}`

Get one mount. `{mount_name}` may be `studio-1` or `/studio-1`.

---

### `PATCH /api/v1/mounts/{mount_name}`

Update fields. Any of: `password`, `title`, `description`, `enabled`.

Changing password or setting `enabled: false` kicks the active source on that mount.

---

### `POST /api/v1/mounts/{mount_name}/rotate-password`

Generate a new source password, kick active source, return new password once.

---

### `DELETE /api/v1/mounts/{mount_name}`

Delete mount and kick active source.  
**Response `204`** (empty body).

```bash
curl -X DELETE https://icecast.ebbersbroadcast.technology/api/v1/mounts/studio-1 \
  -H "Authorization: Bearer $BH_API_TOKEN"
```

---

## Encoder settings (from create response)

| Field | Use in OBS / butt / … |
|-------|------------------------|
| `source_url` | Server hostname |
| `source_port_http` | **`8000`** (Icecast direct — required) |
| `source_mount` | Mount, e.g. `/studio-1` |
| `password` | Source password |
| Username | `source` (or empty, depending on encoder) |

Listeners: open `listen_url` on **HTTPS :443**. Encoding on 80/443 is blocked on purpose (unstable through nginx).

---

## Integration notes

1. Store `password` from create/rotate immediately — it is not returned on `GET` afterwards.
2. Mount appears on the Icecast status page only while a source is connected.
3. Deleting a mount blocks **new** publishes; an active source is also kicked via Icecast admin.
4. Do not call `/internal/*` — that is for nginx auth only.

---

## Quick reference

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | no |
| GET | `/api/v1/mounts` | yes |
| POST | `/api/v1/mounts` | yes |
| PUT | `/api/v1/mounts/{name}` | yes |
| GET | `/api/v1/mounts/{name}` | yes |
| PATCH | `/api/v1/mounts/{name}` | yes |
| POST | `/api/v1/mounts/{name}/rotate-password` | yes |
| DELETE | `/api/v1/mounts/{name}` | yes |
