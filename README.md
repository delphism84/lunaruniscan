## lunaruniscan monorepo

This repository manages three projects in a single monorepo:

- fe app: `lnuniscannerfeapp` (Flutter)
- fe admin: `fe-admin` (Next.js)
- be: `lnuniserverbe` (.NET + Nginx + Docker)

### Structure

```
/lnuniscannerfeapp   # Flutter mobile/desktop/web app
/fe-admin            # Next.js admin web
/lnuniserverbe       # .NET backend, docker-compose, nginx config
/doc                 # documents
```

### Development

- Flutter app: see `lnuniscannerfeapp/README.md` and `pubspec.yaml`
- Admin web: `fe-admin` with Node 20+ (see `package.json`)
- Backend:
  - Node API: `lnuniserverbe/node-api` (Express + socket.io, port 50100)
  - Legacy .NET: `lnuniserverbe/LnUniScannerBE` (deprecated)
  - Reverse proxy + SSL: `lnuniserverbe/nginx-config`, `certbot`
  - Compose: `lnuniserverbe/docker-compose.yml`

### Notes

- Secrets and environment files are ignored via `.gitignore` (e.g., `.env`, `appsettings*.json`).
- For production SSL, map your domains and use Certbot as wired in compose/nginx.
- Uploaded files (images) are stored under `lnuniserverbe/data/api-files` (mounted to container `/usr/src/app/files`).

### Repo

GitHub: `https://github.com/delphism84/lunaruniscan`



