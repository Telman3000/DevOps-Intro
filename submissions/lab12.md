# Lab 12 submission (bonus lab)

Author: Telman Nuruzov (`Telman3000`)
Branch: `feature/lab12`
Fork: https://github.com/Telman3000/DevOps-Intro

Course PR: *(fill after open)*

---

## Layout

```text
wasm/                 # Spin 4 http-go component (moscow-time)
  main.go             # GET /time → Moscow JSON
  spin.toml           # route=/time, allowed_outbound_hosts=[]
  go.mod / go.sum
  main.wasm           # built artifact (~4.6 MB)
wasm-cli/             # Bonus: standalone WASI CLI (TinyGo)
  main.go
  main.wasm           # ~191 KB
submissions/lab12-artifacts/
```

**Tool pins (this machine):** Spin `4.2.1`, TinyGo `0.41.1`, wasmtime `49.0.2`, hyperfine `1.20.0`, `componentize-go` `v0.3.4`, patched Go `1.25.5-wasi-on-idle`.

**Rig:** Windows 10/11 amd64 (build 26200), Docker Desktop for Lab 6 baseline.

> **Spin 4 vs lab text:** Lab 12 prose was validated against Spin 3.x + TinyGo `wasip1` + `-buildmode=c-shared`. `spin new -t http-go` on Spin **4.2.1** scaffolds **Go + `componentize-go`** and `spin-go-sdk/v3`. Followed the scaffold (lab §1.1), not the outdated TinyGo build line.

---

## Task 1 — Spin WASM `/time` (4 pts)

### Scaffold

```text
mkdir wasm && cd wasm
spin new -t http-go moscow-time --accept-defaults
# flattened moscow-time/* → wasm/
```

### `main.go`

See [`wasm/main.go`](../wasm/main.go). Handler registered with `spinhttp.Handle`, returns JSON:

```json
{"unix":1791196497,"iso":"2026-10-05T13:34:57+03:00","hour_minute":"13:34","timezone":"Europe/Moscow","utc_offset":"+03:00"}
```

Moscow via `time.FixedZone("Europe/Moscow", 3*3600)` (no tzdata). JSON built with `fmt.Sprintf` (no `map[string]any`).

### `spin.toml`

See [`wasm/spin.toml`](../wasm/spin.toml):

- `[[trigger.http]] route = "/time"`
- `allowed_outbound_hosts = []`
- build: `componentize-go build` (Spin 4 scaffold)

**Windows build workaround:** `go tool componentize-go` downloads `…-windows-amd64.tar.gz` but releases ship `.zip` → 404. Installed `componentize-go.exe` from the zip; stock Go lacks wasi-on-idle → used `--go` pointing at the patched bootstrap on first successful build. Artifact committed as `wasm/main.wasm`.

### Build + run

```text
$ spin build   # → main.wasm 4 824 779 bytes (~4.6 MB)
$ spin up --listen 127.0.0.1:3000
$ curl -s http://127.0.0.1:3000/time
{"unix":…,"iso":"…+03:00","hour_minute":"…","timezone":"Europe/Moscow","utc_offset":"+03:00"}
```

Evidence: [`lab12-artifacts/spin-build.txt`](lab12-artifacts/spin-build.txt), [`lab12-artifacts/curl-time.json`](lab12-artifacts/curl-time.json), [`lab12-artifacts/spin-up.txt`](lab12-artifacts/spin-up.txt).

### Design questions (a–d)

**a) Browser WASM vs server WASM.** `go build -target=js/wasm` (or `GOOS=js GOARCH=wasm`) produces a module that expects the **browser Go JS runtime** (`wasm_exec.js`) — no WASI, no host syscalls except via JS. Server/`wasip1` (TinyGo) or componentize-go targets **WASI / wasi-http**: you lose browser DOM/JS interop and (with TinyGo) chunks of stdlib, but you gain a portable server sandbox that Spin/wasmtime can host without a browser.

**b) `-buildmode=c-shared` (Spin 3 / TinyGo path).** Spin’s host loads a **reactor-style** module that exports the HTTP handler symbols the SDK registers — not a CLI `_start` that runs once and exits. TinyGo’s `-buildmode=c-shared` (with `wasip1`) produces that export shape. Without it, Spin often returns HTTP 500 / empty component logs. **On Spin 4**, `componentize-go` embeds the component model / wasi-http world instead — same idea (handler exports), different toolchain.

**c) `allowed_outbound_hosts = []` vs Docker `--network none`.** Spin’s capability model is **deny-by-default**: the component cannot open outbound HTTP unless the manifest lists hosts. Docker `--network none` removes the network namespace interface similarly for that container, but the broader Linux namespace/cgroup model is coarser (process can still be powerful inside the box if other mounts/caps leak). WASM’s grants are per-component and finer (clock/fs/net individually).

**d) Stdlib gaps hit.** Avoided `time.LoadLocation("Europe/Moscow")` (no embedded tzdata in the WASM image) and reflection-heavy `encoding/json` of `map[string]any` — used `FixedZone` + `fmt.Sprintf` JSON. (Spin 4 path uses full Go via componentize-go; the same pitfalls are classic TinyGo gotchas and still good hygiene.)

---

## Task 2 — Perf vs Lab 6 Docker (4 pts)

Endpoints: Spin `GET /time` vs Lab 6 `GET /health` on already-running runtimes. Warm: `hyperfine --warmup 5 --runs 50`. Cold: kill/restart, time to first HTTP 200 (≥5 samples).

| Dimension | Lab 6 Docker (`quicknotes:lab6`) | Lab 12 WASM/Spin |
|-----------|--------------------------------:|-----------------:|
| Artifact size | **22.6 MB** (`docker images`); 5.36 MB uncompressed (`inspect`) | **4.60 MB** (`main.wasm`) |
| Cold start (p50) | **380.4 ms** (samples 456 / 371 / 380 / 386 / 375) | **193.5 ms** (samples 222 / 173 / 194 / 196 / 161) |
| Warm latency p50 | **43.1 ms** | **44.0 ms** |
| Warm latency p95 | **96.1 ms** | **114.1 ms** |

Raw logs: [`lab12-artifacts/hyperfine-warm.txt`](lab12-artifacts/hyperfine-warm.txt), [`lab12-artifacts/cold-start.txt`](lab12-artifacts/cold-start.txt).

### Design questions (e–g)

**e) What dominates cold start?** Docker: image layer setup + containerd/dockerd plumbing + namespace/cgroup init + process start of the Go binary. Spin: load/compile the WASM component into wasmtime + instantiate + bind the wasi-http listener — much less OS virtualization overhead, so ~2× faster cold here.

**f) When WASM vs Docker?** WASM wins for **short-lived multi-tenant edge/FaaS**, tiny artifacts, fast scale-to-zero (Reading 12 table: cold start, size, isolation). Docker still right for **full Linux ABI**, cgo/native libs, long-lived stateful services, rich debugging, and the existing container ecosystem.

**g) Multi-tenant safety.** Capability sandbox makes **filesystem / SSRF / “escape via `/proc` + sibling containers”** style attacks harder: a tenant module cannot see host paths or dial arbitrary hosts unless granted. Namespaces are strong but historically leakier (shared kernel, misconfigured mounts/caps).

---

## Bonus — Two WASM execution models (2 pts)

### Build / run

```text
# wasm-cli (TinyGo WASI CLI — needs Go ≤1.26 for TinyGo 0.41; used Go 1.25.5 + wasm-opt/binaryen)
cd wasm-cli
tinygo build -o main.wasm -target=wasi -no-debug ./main.go

wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time main.wasm
# → {"unix":…,"iso":"…+03:00","hour_minute":"…",…}
```

Evidence: [`lab12-artifacts/wasmtime-run.txt`](lab12-artifacts/wasmtime-run.txt), [`lab12-artifacts/wasm-cli-compare.txt`](lab12-artifacts/wasm-cli-compare.txt).

### Comparison

| | Spin component (`wasm/main.wasm`) | WASI CLI (`wasm-cli/main.wasm`) |
|--|--:|--:|
| Size | 4 824 779 B (~4.6 MB) | **195 211 B (~191 KB)** |
| Cold / invoke | Spin server cold ~194 ms (then warm ~44 ms/req) | **wasmtime run p50 ~36 ms** per invocation |
| Model | Persistent wasi-http server | Per-invocation CGI-style CLI |

### Design questions (h–j)

**h) Why can’t the Spin component run under bare `wasmtime run`?** It is a **wasi-http component** (handler exports for an HTTP host), not a WASI CLI module with `_start` that prints to stdout. Bare `wasmtime run` expects the CLI world; use `wasmtime serve` (or Spin) for wasi-http.

**i) What does Spin add on top of wasmtime?** Instance pooling / reuse, the **wasi-http server loop**, **manifest routing** (`spin.toml` triggers), and **outbound-host policy** (`allowed_outbound_hosts`) — ops glue around the same engine.

**j) When each fits.** Per-invocation `wasmtime run`: batch/CLI transforms, CI one-shots, CGI-like request handlers. Spin persistent server: low-latency HTTP APIs at the edge where you want warm instances and route many requests through one process.

---

## Acceptance checklist

- [x] Scaffolded from `spin new -t http-go` (Spin 4 / componentize-go / sdk v3)
- [x] `spin build` → `main.wasm`; `spin up` serves Moscow JSON on `/time`
- [x] Design a–d
- [x] Perf table with real cold/warm/size numbers
- [x] Design e–g
- [x] `wasm-cli/` + `wasmtime run` + comparison
- [x] Design h–j
