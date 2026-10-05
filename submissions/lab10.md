# Lab 10 submission

Author: Telman Nuruzov (`Telman3000`)
Branch: `feature/lab10`
Fork: https://github.com/Telman3000/DevOps-Intro
Image: `ghcr.io/telman3000/devops-intro/quicknotes`

Course PR: https://github.com/inno-devops-labs/DevOps-Intro/pull/1728

---

## Layout

```text
.github/workflows/release.yml   # tag v* → build → ghcr.io → Render hook
cloud/
├── render.md                   # Option A settings
├── teardown.md
└── devcontainer.md             # Option B notes
.devcontainer/devcontainer.json # Option B fallback
scripts/lab10-latency.ps1
```

---

## Task 1 — CI push to `ghcr.io`

### Workflow

[`.github/workflows/release.yml`](../.github/workflows/release.yml)

- Trigger: `push` of tags `v*`
- Build context: `./app` (`app/Dockerfile`), platform `linux/amd64`
- Push: `ghcr.io/telman3000/devops-intro/quicknotes:<tag>` **and** `:latest`
- Permissions: `contents: read`, `packages: write` only
- Actions pinned by SHA: `checkout@11bd7190…`, `setup-buildx@e468171a…`, `login-action@74a5d142…`, `build-push-action@26343531…`
- After push: optional Render deploy hook via secret `RENDER_DEPLOY_HOOK`

### Release commands (run by student)

```powershell
git tag -a v0.1.0 -m "Lab 10 release"
git push origin v0.1.0
```

(`-s` GPG sign optional if you have a signing key configured.)

### Evidence (fill after green run)

| Item | Value |
|------|--------|
| Registry URL | `ghcr.io/telman3000/devops-intro/quicknotes:v0.1.0` |
| Package visibility | **Public** |
| Actions run URL | green `release` / `build-and-push` (~51s) |
| Clean pull | OK — `Downloaded newer image … Digest: sha256:8399292f90bd5166c643ec577e2154dc5e52cd442c23f6c88ebacf2cf0b5037c` |

### Design questions (a–c)

**a)** `GITHUB_TOKEN` + `packages: write` is enough for **same-repo** GHCR pushes. Reach for **OIDC** when pushing to a *different* cloud (AWS ECR, GCP Artifact Registry, Azure ACR) or a *different* GitHub org’s registry without long-lived PATs — OIDC gives short-lived, audience-bound tokens with no stored cloud credentials in Actions secrets.

**b)** `:v0.1.0` is the immutable pin for prod / rollbacks / SBOMs. `:latest` is a convenience floating pointer for “give me whatever we currently call stable” in demos, `docker pull …:latest` docs, and for humans who refuse to read changelogs. You ship both; you **deploy** the immutable tag.

**c)** Least privilege: the job token can publish packages but cannot rewrite repo settings, create deploy keys, or modify Actions secrets. A compromised build cannot silently escalate to `write:all` and, e.g., push malware to `main` or exfiltrate other secrets via workflow edits.

---

## Task 2 — Deploy (**Option B: GitHub Codespaces**)

**Choice:** Option B — **GitHub Codespaces**, not Render.

**Why:** Render Free still showed **Add Card** / card verification for this account; Russian cards are rejected (same issue Dmitriy flagged in the course chat). Lab text + pinned update: switch to Codespaces when Render asks for a card. No card, GitHub account only.

Docs: [`cloud/devcontainer.md`](../cloud/devcontainer.md), checked-in [`.devcontainer/devcontainer.json`](../.devcontainer/devcontainer.json).

(`cloud/render.md` kept as the Option A attempt notes; not used for scoring.)

### Codespace setup

1. After `ghcr.io/.../quicknotes:v0.1.0` is public (Task 1)
2. On the fork: **Code → Codespaces → Create codespace on `feature/lab10`**
   (or `gh codespace create -r Telman3000/DevOps-Intro -b feature/lab10`)
3. `postStartCommand` pulls/runs the image and binds `:8080`
4. **Ports** tab → port `8080` → visibility **Public**  
   (or `gh codespace ports visibility 8080:public -c <name>`)
5. Public URL form: `https://<codespace-name>-8080.app.github.dev`

### Public URL + health

```text
URL: https://fluffy-garbanzo-7g66w6xx7rqhqwr-8080.app.github.dev
Codespace: fluffy-garbanzo
Port 8080 visibility: Public
Image: ghcr.io/telman3000/devops-intro/quicknotes:v0.1.0 (healthy)

$ curl -sS https://fluffy-garbanzo-7g66w6xx7rqhqwr-8080.app.github.dev/health
{"notes":4,"status":"ok"}
HTTP=200
```

Also `GET /notes` returns seed notes JSON (public, no GitHub login required from this machine).

### “Scale-to-zero” for Codespaces (manual stop/start)

A stopped codespace does **not** wake on HTTP — that is the line vs Render. Measure:

1. **Warm p50:** 5× `GET /health` while running  
2. **3× cold (manual):** `gh codespace stop -c <name>` → curl public URL (record response) → start again → time until `/health` returns 200  
3. **Note persistence:** `POST /notes`, stop codespace, start again, `GET /notes`

| Metric | Value |
|--------|------:|
| Warm p50 (5 GET /health) | **0.367 s** (samples: 0.371, 0.369, 0.367, 0.286, 0.297) |
| Stop→curl #1 | **HTTP=502** (~0.62–0.67 s) — does not wake |
| Start→`/health` 200 #1 | Codespace Active, then `docker run` + Port **Public** again; first public `200` in **~0.93 s** once container up (earlier probes were **302** while Private / empty DinD) |
| Note after stop/start #1 | **GONE** — only 4 seed notes; `lab10-persist` absent (DinD container + `/data` recreated) |
| Stop→curl #2 / Start #2 | Stop→**HTTP=404** (~0.80 s); after Start+docker+Public → **HTTP=200** (~0.71 s) |
| Stop→curl #3 / Start #3 | Same pattern (stop does not wake); after Start+docker+Public → **HTTP=200** (~0.85 s) |

**Expected note result:** with Docker-in-Docker the QuickNotes container (and its `/data`) is **recreated** after stop/start → the POSTed note is **gone** (only seed remains). That differs from a plain codespace file on the workspace disk, and matches the “ephemeral app state” lesson (similar outcome to Render Free FS, different mechanism).

### Design questions (d–f) — Option B answers

**d)** Render spin-down **wakes on the next request**; a stopped codespace **does not**. That wake-on-request line is what separates a hosting platform from a cloud **dev environment**.

**e)** GitHub’s terms treat Codespaces as development VMs, not production hosts (no SLA, quota, not meant for public traffic). To call QuickNotes “production” you’d need durable hosting, monitoring/alerts, backups, auth, a stable URL, and a real deploy pipeline — not a personal codespace.

**f)** On this setup the note **vanished** after stop/start because DinD drops the container and its writable layer/`/data`. Workspace files on the codespace disk would survive; the *app* data did not. Render Free also loses notes (ephemeral service FS) — same user-visible outcome, different reason.

---

## Bonus — Cloudflare Tunnel + comparison

`cloudflared` is installed locally (`2026.9.3`).

### Quick tunnel (measured)

```text
URL: https://bundle-coastal-minimal-improved.trycloudflare.com
GET /health → {"notes":29,"status":"ok"}
```

Command: `cloudflared tunnel --url http://localhost:8080`  
(ephemeral — changes on restart)

**Verify from phone / cellular** (different network): open  
`https://bundle-coastal-minimal-improved.trycloudflare.com/health`

Warm latency, 50 GETs `/health` via tunnel ([`tunnel-warm.txt`](lab10-artifacts/tunnel-warm.txt)):

```text
tunnel warm n=50 p50=0.476s p95=0.516s min=0.436 max=0.608
```

### Comparison table

| Metric | Codespace (Option B) | Cloudflare Tunnel (local-via-edge) |
|--------|---------------------:|-----------------------------------:|
| Warm p50 | **0.367 s** | **0.476 s** |
| Warm p95 | ~0.37 s (n=5) | **0.516 s** |
| Cold start | 3× stop→404/502 (no wake); start+docker+Public → first `200` ~0.7–0.9 s once ready | N/A (continuously local) |
| Public URL stability | stable while codespace exists | ephemeral on restart |
| Cost | free (quota) | free |

Screenshot / note: verified from phone cellular → _(you: open the tunnel URL on LTE)_ 

### Design questions (g–i)

**g)** “Really cloud” usually means the **compute** lives in the provider’s DC (Render). Tunnel is **edge proxy + your laptop as origin**. Users mostly care about URL reachability and latency — until your laptop sleeps and the “cloud” URL dies.

**h)** Render warm: geographic RTT to Frankfurt + TLS + free-tier noisy neighbors. Tunnel warm: path is client → Cloudflare edge → your home uplink → localhost; often the **home uplink / Wi-Fi** dominates, not the app.

**i)** Tunnel is right for home labs, on-prem demos, reviewer previews without deploying. Never for always-on production SLA, multi-region HA, or when the origin machine is a student laptop that closes at midnight.

---

## How to finish (checklist for you)

1. Push `feature/lab10` (**you** push)
2. Tag release for Task 1: `git tag -a v0.1.0 -m "Lab 10 release"` && `git push origin v0.1.0`
3. Flip GHCR package → **Public**; clean `docker pull`
4. **Skip Render** (card wall) → create **Codespace** on `feature/lab10`
5. Make port `8080` **Public**; fill URL + warm/stop/start numbers in this file
6. Bonus: open tunnel URL from phone LTE (tunnel may need restart if dead)
7. PR `feature/lab10` → course `main`; Moodle — write **Option B / why card**
