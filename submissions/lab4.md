# Lab 4 submission

Author: Telman Nuruzov (`Telman3000`)
Branch: `feature/lab4`
Fork: https://github.com/Telman3000/DevOps-Intro
Environment: WSL2 Ubuntu 24.04 (Windows host)

Course PR: https://github.com/inno-devops-labs/DevOps-Intro/pull/1581

> **Port note:** In this WSL, `:8080` is occupied by Airflow (gunicorn). QuickNotes was run on **`:18080`** and the TLS front on **`:18443`** so captures hit the real QuickNotes process, not Airflow.

---

## Task 1 — Trace a request end-to-end

### Capture

- `tcpdump -i lo -nn -s 0 -A 'tcp port 18080' -w lab4-trace.pcap`
- Request: `curl -4 -v -X POST http://127.0.0.1:18080/notes -H 'Content-Type: application/json' -d '{"title":"trace me","body":"in flight"}'`
- Decoded text: [`lab4-trace.txt`](lab4-trace.txt) / raw [`lab4-artifacts/lab4-trace.pcap`](lab4-artifacts/lab4-trace.pcap)

### Annotated trace (highlights)

**TCP three-way handshake** (`Flags [S]` → `[S.]` → `[.] ack`):

```text
IP 127.0.0.1.47586 > 127.0.0.1.18080: Flags [S], ...
IP 127.0.0.1.18080 > 127.0.0.1.47586: Flags [S.], ... ack ...
IP 127.0.0.1.47586 > 127.0.0.1.18080: Flags [.], ack 1, ...
```

**HTTP request** (`POST /notes` + JSON body):

```text
POST /notes HTTP/1.1
Host: 127.0.0.1:18080
Content-Type: application/json
Content-Length: 39

{"title":"trace me","body":"in flight"}
```

**HTTP response** (`201 Created` + note JSON):

```text
HTTP/1.1 201 Created
Content-Type: application/json
Content-Length: 92

{"id":5,"title":"trace me","body":"in flight","created_at":"..."}
```

**Connection close** (FINs + final ACK):

```text
Flags [F.], seq 176, ack 206, ...
Flags [F.], seq 206, ack 177, ...
Flags [.], ack 207, ...
```

Full curl transcript: [`lab4-artifacts/curl-post.txt`](lab4-artifacts/curl-post.txt)  
Health probe before capture: `{"notes":4,"status":"ok"}` ([`lab4-artifacts/health-check.txt`](lab4-artifacts/health-check.txt))

### 1.3 Five debugging commands

Full output: [`lab4-artifacts/task1-debug-commands.txt`](lab4-artifacts/task1-debug-commands.txt)

| # | Command | Result / decision |
|---|---------|-------------------|
| 1 | `ss -tlnp \| grep :18080` | QuickNotes **LISTEN** on `*:18080` (pid shown) |
| 2 | `ip route show` | Default via `172.22.240.1` on `eth0` (WSL NAT) |
| 3 | `mtr -rwc 5 localhost` | `mtr` unavailable (apt mirrors unreachable from WSL); **`ping -c 5 localhost`** — 0% loss |
| 4 | `dig +short example.com @1.1.1.1` | UDP to `1.1.1.1:53` **timed out** from WSL; same query from Windows host succeeded — see [`lab4-artifacts/dig-windows-1.1.1.1.txt`](lab4-artifacts/dig-windows-1.1.1.1.txt) (`104.20.23.154`, `172.66.147.243`) |
| 5 | `journalctl --user -u quicknotes` | No entries (app run as foreground binary, not a user systemd unit) |

Also noted: `ss` still shows **foreign** listener on `:8080` (Airflow) — reason we did not use the lab’s default port.

### If QuickNotes returned 502 — what first?

I would first check whether anything is still **listening** on the expected port (`ss -tlnp`) and whether **health** returns from the host (`curl /health`). A 502 usually means a reverse proxy/load balancer is up but the upstream is down, mis-addressed, or crashing — so confirm the process, the listen address/port, and the proxy’s upstream target before touching DNS or the app code. Packet capture / access logs then show whether the TCP session even reaches QuickNotes.

---

## Task 2 — Outside-in debugging on a broken deploy

### Reproduce

1. First `ADDR=:18080 ./quicknotes` (holds the port)
2. Second `ADDR=:18080 ./quicknotes` → fails

Exact error ([`lab4-artifacts/qn-broken.log`](lab4-artifacts/qn-broken.log)):

```text
listen: listen tcp :18080: bind: address already in use
```

### Outside-in chain

Full log: [`lab4-artifacts/task2-outside-in.txt`](lab4-artifacts/task2-outside-in.txt)

| Step | Command | Output / decision |
|------|---------|-------------------|
| 1 Running? | `ps -ef \| grep quicknotes` | One healthy `./quicknotes` (first instance) |
| 2 Listening? | `ss -tlnp \| grep 18080` | **LISTEN** — port held by first process |
| 3 Reachable? | `curl …/health` | **200** + `{"notes":5,"status":"ok"}` — first instance serves traffic; second never bound |
| 4 Firewall? | `iptables` / `nft` | No rules output — not a firewall symptom |
| 5 DNS? | dig/getent `localhost` | `127.0.0.1` — DNS fine |

**Root cause:** second process could not `bind()` — **`address already in use`**.

### Repair

Killed the first holder, restarted one instance, re-checked health ([`lab4-artifacts/task2-repaired.txt`](lab4-artifacts/task2-repaired.txt)):

```text
{"notes":5,"status":"ok"}
LISTEN ... *:18080 ... users:(("quicknotes",...))
```

### Mini-postmortem (blameless)

This is a **shared scarce resource** failure: a TCP port can be owned by only one listener. It is systemic whenever deploy scripts, local Airflow, leftover `go run`, or a previous container reuse the same `ADDR` without a readiness/preflight check. Prevention is tooling, not blame: refuse to start if `ss` already shows the port; allocate ephemeral ports in lab/dev; use systemd socket activation or a process supervisor that tracks the unit; and make health checks fail closed in CI/CD before advertising the service. The outside-in order (process → listen → HTTP → firewall → DNS) keeps the investigation short when the symptom is “second copy won’t start” vs “nothing answers.”

---

## Bonus — Decode the TLS handshake

QuickNotes stays HTTP. A small local TLS reverse proxy (`scripts/tlsproxy.go`) terminated TLS on `127.0.0.1:18443` and proxied to QuickNotes on `:18080` (Caddy was attempted first; `tls internal` returned TLS alerts in this WSL, so the Go proxy + self-signed cert was used).

### Capture

- `tcpdump … 'tcp port 18443' -w lab4-tls.pcap` → [`lab4-tls.pcap`](lab4-tls.pcap)
- `curl -4 -vk --http1.1 https://127.0.0.1:18443/health` → [`lab4-artifacts/curl-tls-health.txt`](lab4-artifacts/curl-tls-health.txt)
- `openssl s_client -connect 127.0.0.1:18443 -servername localhost -showcerts` → [`lab4-artifacts/openssl-showcerts.txt`](lab4-artifacts/openssl-showcerts.txt)

### ClientHello / ServerHello (from `curl -vk`)

```text
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256 / X25519 / id-ecPublicKey
```

Wireshark was not installed (apt mirrors unreachable from WSL). Handshake steps are evidenced by curl’s verbose TLS decode + openssl certificate dump + `lab4-tls.pcap` (openable in Wireshark offline). Packet summary: [`lab4-artifacts/tls-handshake-notes.txt`](lab4-artifacts/tls-handshake-notes.txt)

### Certificate chain (`openssl s_client -showcerts`)

- Subject / issuer: `CN = localhost` (self-signed)
- Protocol: **TLSv1.3**, cipher **TLS_AES_128_GCM_SHA256**
- Upstream health through TLS: `HTTP/1.1 200` + `{"notes":5,"status":"ok"}`

### Which negotiation step kills TLS 1.0 / 1.1 in 2026?

The **version negotiation inside ClientHello / ServerHello**: modern clients advertise a supported_versions (or legacy `client_version` capped at 1.2 with extensions) that no longer includes 1.0/1.1, and servers configured with a minimum of TLS 1.2+ **reject** any negotiated 1.0/1.1 (alert / handshake failure). Browsers and OpenSSL 3 defaults have removed 1.0/1.1; a 2026 stack that still offered them would fail compliance and most peer policies. Our capture negotiated **TLS 1.3 only** — there is no path back to 1.0/1.1 once both sides enforce modern minima.

---

## Artifacts index

| File | Purpose |
|------|---------|
| `lab4-trace.txt` / `.pcap` | Task 1 HTTP/TCP capture |
| `lab4-tls.pcap` | Bonus TLS capture |
| `lab4-artifacts/*` | Command outputs, curl/openssl logs |
| `scripts/lab4-collect.sh`, `lab4-bonus-tls.sh`, `tlsproxy.go` | Repro helpers (optional) |
