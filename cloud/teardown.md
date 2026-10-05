# Teardown (Lab 10)

## Render (Option A)

1. [dashboard.render.com](https://dashboard.render.com) → your QuickNotes web service
2. **Settings** → scroll to **Delete Web Service** (or Suspend)
3. Confirm deletion
4. Optional: remove GitHub Actions secret `RENDER_DEPLOY_HOOK`

Free instance hours cost $0; leaving it running is fine for demos, but delete when the course ends to avoid surprise email noise.

## Codespaces (Option B, if used)

```bash
gh codespace list
gh codespace delete -c <name> --force
```

Stopped codespaces still consume the **15 GB** storage quota — delete, don’t just stop.

## Cloudflare quick tunnel (Bonus)

Ctrl+C the `cloudflared tunnel --url …` process. Ephemeral URL dies with it; nothing else to clean up.
