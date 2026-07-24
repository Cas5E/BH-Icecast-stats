# Multi-server deployments

Each Icecast server gets its **own** env file with its own domain and secrets.
The same Docker stack is reused; only environment variables change.

## Layout

```
deployments/
  template.env                 # committed template
  stream.example.com.env       # local/gitignored — one file per server
  icecast.ebbersbroadcast...   # another instance
```

`deployments/*.env` is gitignored (except `template.env`).

## New instance

```bash
bash scripts/new-instance.sh \
  --domain stream.klant.nl \
  --email admin@klant.nl \
  --ssh-host 203.0.113.10
```

Creates `deployments/stream.klant.nl.env` with random secrets.

## Deploy to that server

DNS A-record for the domain must already point to the server.

```bash
bash scripts/deploy-instance.sh --env deployments/stream.klant.nl.env
```

Or override host:

```bash
bash scripts/deploy-instance.sh \
  --env deployments/stream.klant.nl.env \
  --host 203.0.113.10 \
  --user root
```

What it does:

1. Installs Docker if needed  
2. Syncs the project to `/opt/bh-icecast` (or `DEPLOY_REMOTE_DIR`)  
3. Uploads that instance’s `.env`  
4. `docker compose up -d --build`  
5. Let’s Encrypt for `BH_DOMAIN`  
6. Prints API token hint + URLs  

## Update an existing instance

```bash
bash scripts/deploy-instance.sh --env deployments/stream.klant.nl.env --skip-ssl
```

## Per-instance checklist

| Item | Where |
|------|--------|
| Domain | `BH_DOMAIN` / `BH_PUBLIC_LISTEN_BASE` |
| Let’s Encrypt email | `LETSENCRYPT_EMAIL` |
| API token | `BH_API_TOKEN` (unique per server) |
| Icecast master secrets | `ICECAST_*_PASSWORD` (unique per server) |

Mounts/databases are **per server** (Docker volume `api-data`) — not shared across hosts.
