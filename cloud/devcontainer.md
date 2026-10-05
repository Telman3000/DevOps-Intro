# Codespaces fallback (Lab 10 Option B)

Use only if Render asks for a card / Russian card fails.

## `.devcontainer/devcontainer.json` (also in repo root `.devcontainer/`)

See the checked-in file. It:

- Uses a Docker-in-Docker capable base (`mcr.microsoft.com/devcontainers/base:ubuntu`)
- Pulls / runs `ghcr.io/telman3000/devops-intro/quicknotes:v0.1.0` on start
- Forwards port `8080`

## Commands

```bash
# one-time scopes
gh auth refresh -h github.com -s codespace

gh codespace create -r Telman3000/DevOps-Intro -b feature/lab10
gh codespace ports visibility 8080:public -c <name>
gh codespace ports -c <name>
# → https://<codespace>-8080.app.github.dev/health
```

Visibility is **not** settable in `devcontainer.json` — re-check after every restart.
