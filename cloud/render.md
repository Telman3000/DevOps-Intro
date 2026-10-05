# Render — QuickNotes (Lab 10, Option A)

## Why Existing Image (not “build from repo”)

We deploy the **same** image Lab 9 scanned and Task 1 pushed to GHCR:

`ghcr.io/telman3000/devops-intro/quicknotes:v0.1.0`

Pros vs Render building from git:

- **Reproducibility** — bit-identical to the CI artifact / Trivy SBOM target
- **No second build cache** on Render’s builders
- **Deploy hook** can retarget only the tag via `imgURL`

## Service settings (dashboard)

| Setting | Value |
|---------|--------|
| Type | Web Service |
| Instance | **Free** (switch off the paid default) |
| Region | Frankfurt (`frankfurt`) — closest for Innopolis |
| Source | **Existing Image** |
| Image | `ghcr.io/telman3000/devops-intro/quicknotes:v0.1.0` |
| Health check path | `/health` |
| Auto-Deploy | via GitHub Actions deploy hook (not git auto-deploy) |

## Environment variables (port alignment)

Render injects `PORT` (default `10000`). QuickNotes listens on `ADDR` (default `:8080`).
To avoid `New primary port detected … Restarting deploy`, set both explicitly:

| Key | Value | Why |
|-----|-------|-----|
| `PORT` | `8080` | Tell Render’s proxy which port to route |
| `ADDR` | `:8080` | Tell QuickNotes which address to bind |
| `DATA_PATH` | `/data/notes.json` | same as Lab 6 (ephemeral on Free) |
| `SEED_PATH` | `/seed.json` | baked into the image |

No Dockerfile / QuickNotes code changes — configuration only.

## Deploy hook (secret)

1. Render → Service → **Settings** → **Deploy Hook** → copy URL
2. GitHub fork → **Settings → Secrets and variables → Actions**
3. New secret name: `RENDER_DEPLOY_HOOK`
4. Value: the full hook URL (contains `key=…`)

The Lab 10 `release` workflow appends `&imgURL=` (URL-encoded) after a successful `ghcr.io` push so a new `v*` tag redeploys Render.

## Public URL

Fill after first successful deploy:

- Service URL: `https://________________.onrender.com`
- Verified: `curl -sS https://….onrender.com/health` → `{"status":"ok",…}`

## Notes on Free tier

- Spins down after ~15 min idle; next request is a **cold start** (~30–90 s)
- Filesystem is **ephemeral** — notes written with `POST /notes` disappear after spin-down / redeploy
