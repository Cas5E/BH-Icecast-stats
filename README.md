# BH-Icecast

Modulaire Icecast-stack met HTTP-API voor mountpoints. Elk mountpoint heeft een **eigen source-wachtwoord**. Mounts aanmaken/wijzigen vereist **geen Icecast-reload**.

Zelfde stack op **meerdere servers** met elk een eigen domein: zie [docs/DEPLOY.md](docs/DEPLOY.md).

## Hoe het werkt (zonder disconnects)

Icecast kent alleen een intern master source-wachtwoord en maakt mounts dynamisch aan zodra een source connect.

Nginx:

1. checkt het source-wachtwoord via de API (`auth_request`)
2. vervangt de credentials door het Icecast-masterwachtwoord
3. proxyt de stream naar Icecast

```
Encoder  --SOURCE/PUT-->  :80 of :443 nginx  -->  Icecast
Listeners --GET ------->  :443 nginx         -->  Icecast
Beheer    --API -------->  IP-allowlist / SSH-tunnel
```

## Multi-server (aanbevolen)

```bash
# 1) Nieuwe instance (eigen secrets + domain)
bash scripts/new-instance.sh \
  --domain stream.klant.nl \
  --email admin@klant.nl \
  --ssh-host 203.0.113.10 \
  --allow-ip 198.51.100.20

# 2) DNS A-record naar de server zetten

# 3) Deploy
bash scripts/deploy-instance.sh --env deployments/stream.klant.nl.env
```

Details: [docs/DEPLOY.md](docs/DEPLOY.md) · API: [docs/API.md](docs/API.md)

## Snel starten (één server, handmatig)

```bash
cp .env.example .env   # BH_DOMAIN + secrets invullen
# of: bash scripts/generate-secrets.sh
docker compose up -d --build
bash scripts/init-ssl.sh
```

- Streams: `https://<domain>/<mount>`
- API/docs: alleen vanaf `BH_API_ALLOW_IPS` of `ssh -L 8080:127.0.0.1:8080 ...` → `http://127.0.0.1:8080`

## Bare-metal (Debian/Ubuntu)

```bash
sudo bash scripts/install-baremetal.sh
```

Installeert Icecast2, Nginx, de API (systemd) en schrijft secrets naar `/etc/bh-icecast.env`.

## API

Alle beheer-endpoints vereisen:

```http
Authorization: Bearer <BH_API_TOKEN>
```

### Mount aanmaken

```bash
curl -s -X POST http://localhost:8080/api/v1/mounts \
  -H "Authorization: Bearer $BH_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"live","title":"Studio Live"}'
```

Response (wachtwoord wordt één keer teruggegeven):

```json
{
  "name": "/live",
  "password": "....",
  "listen_url": "http://localhost:8000/live",
  "source_mount": "/live",
  "enabled": true
}
```

### Overzicht / wijzigen / verwijderen

```bash
# lijst
curl -H "Authorization: Bearer $BH_API_TOKEN" http://localhost:8080/api/v1/mounts

# wachtwoord roteren
curl -X POST -H "Authorization: Bearer $BH_API_TOKEN" \
  http://localhost:8080/api/v1/mounts/live/rotate-password

# uitschakelen (nieuwe sources geweigerd; actieve stream blijft tot disconnect)
curl -X PATCH -H "Authorization: Bearer $BH_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":false}' \
  http://localhost:8080/api/v1/mounts/live

# verwijderen
curl -X DELETE -H "Authorization: Bearer $BH_API_TOKEN" \
  http://localhost:8080/api/v1/mounts/live
```

Optioneel eigen wachtwoord bij create/update:

```json
{ "name": "live", "password": "super-geheim-wachtwoord" }
```

## Encoder instellen (OBS / butt)

| Veld | Waarde |
|------|--------|
| Server | `http://<host>` |
| Poort | `8000` |
| Mount | `/live` (of jouw mount) |
| Password | source-wachtwoord uit de API |
| Gebruikersnaam | `source` (of leeg — afhankelijk van encoder) |

Geen luisterwachtwoord: iedereen met de listen-URL kan meeluisteren.

## Structuur

```
BH-Icecast/
  api/           FastAPI management + source-auth
  icecast/       Icecast image + template config
  nginx/         Auth-proxy (streams + API poort)
  scripts/       Secrets + bare-metal installer
  docker-compose.yml
```

## Security notes

- Geef `ICECAST_SOURCE_PASSWORD` nooit aan broadcasters — alleen de proxy gebruikt die.
- Zet `BH_API_TOKEN` sterk en houd poort 8080 niet publiek open zonder TLS/firewall als dat kan.
- Icecast admin UI is geblokkeerd via nginx (`/admin` → 403).
