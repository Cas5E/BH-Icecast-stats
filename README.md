# BH-Icecast

Modulaire Icecast-stack met HTTP-API voor mountpoints. Elk mountpoint heeft een **eigen source-wachtwoord**. Mounts aanmaken/wijzigen vereist **geen Icecast-reload** — bestaande listeners blijven verbonden.

## Hoe het werkt (zonder disconnects)

Icecast kent alleen een intern master source-wachtwoord en maakt mounts dynamisch aan zodra een source connect.

Broadcasters verbinden naar poort **8000** met hun mount-specifieke wachtwoord. Nginx:

1. checkt het wachtwoord via de API (`auth_request`)
2. vervangt de credentials door het Icecast-masterwachtwoord
3. proxyt de stream naar Icecast

Listeners (GET) gaan rechtstreeks door zonder source-auth.

```
OBS / butt  --SOURCE/PUT + mount-password-->  :8000 nginx  -->  Icecast
Listeners   --GET /mount ------------------>  :8000 nginx  -->  Icecast
Beheer      --HTTP Bearer token ----------->  :8080 API
```

## Snel starten (Docker)

Op een Linux-host met Docker:

```bash
cp .env.example .env
# of: bash scripts/generate-secrets.sh
# vul BH_DOMAIN + secrets in .env

docker compose up -d --build
bash scripts/init-ssl.sh
```

- Streams: `https://<domain>/<mount>`
- API: `https://<domain>/api/v1/...`
- Docs: `https://<domain>/docs`
- Health: `https://<domain>/health`

Poorten **80** (ACME + redirect) en **443** (HTTPS). Geen aparte 8000/8080 naar buiten.

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
