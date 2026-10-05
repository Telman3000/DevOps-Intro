# Lab 9 submission

Author: Telman Nuruzov (`Telman3000`)
Branch: `feature/lab9`
Fork: https://github.com/Telman3000/DevOps-Intro
Tools: Trivy `aquasec/trivy:0.59.1`, ZAP `ghcr.io/zaproxy/zaproxy:2.16.1`, govulncheck `v1.1.4`

Course PR: https://github.com/inno-devops-labs/DevOps-Intro/pull/1727

---

## Layout

```text
app/
├── security.go          # SecurityHeaders middleware
├── security_test.go     # asserts headers; fails without middleware
├── handlers.go          # Routes() wraps mux with SecurityHeaders
└── Dockerfile
.github/workflows/ci.yml # + govulncheck job (bonus)
submissions/
├── lab9.md
└── lab9-artifacts/
    ├── trivy-image.txt / .json
    ├── trivy-fs.txt
    ├── trivy-config.txt
    ├── sbom-cyclonedx.json
    ├── zap-before/ zap-after/
    └── govulncheck-red.txt / green.txt
```

---

## Task 1 — Trivy: image + filesystem + config + SBOM

Pinned scanner: **`aquasec/trivy:0.59.1`** (not `:latest`).

### 1.1 Image scan (`trivy image --severity HIGH,CRITICAL`)

Command:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.59.1 image --severity HIGH,CRITICAL quicknotes:lab6
```

Top of output ([`trivy-image.txt`](lab9-artifacts/trivy-image.txt)):

```text
quicknotes:lab6 (debian 12.15)
==============================
Total: 0 (HIGH: 0, CRITICAL: 0)

healthcheck (gobinary)
======================
Total: 19 (HIGH: 19, CRITICAL: 0)

quicknotes (gobinary)
=====================
Total: 19 (HIGH: 19, CRITICAL: 0)
```

OS packages on distroless: **0 HIGH/CRITICAL**. All HIGH findings are **Go stdlib** embedded in the static binaries (`v1.24.13`), fixed only in **Go 1.25+/1.26+** (course still pins 1.24).

Full JSON: [`trivy-image.json`](lab9-artifacts/trivy-image.json).

### 1.2 Filesystem scan (`trivy fs --severity HIGH,CRITICAL`)

```bash
docker run --rm -v "${PWD}:/src" -w /src \
  aquasec/trivy:0.59.1 fs --severity HIGH,CRITICAL /src
```

Top of output ([`trivy-fs.txt`](lab9-artifacts/trivy-fs.txt)):

```text
## Summary
- Language deps (app/go.mod): 0 HIGH / 0 CRITICAL
- Secret findings: 1 HIGH

## Finding
Target: .vagrant/machines/default/virtualbox/private_key (secrets)
Severity: HIGH
Category: AsymmetricPrivateKey (OpenSSH private key)
```

(Key material intentionally redacted from the committed artifact; path is gitignored.)

### 1.3 Config scan (`trivy config`)

```bash
docker run --rm -v "${PWD}:/src" -w /src \
  aquasec/trivy:0.59.1 config --severity HIGH,CRITICAL /src
```

Result ([`trivy-config.txt`](lab9-artifacts/trivy-config.txt)): **0 HIGH / 0 CRITICAL** misconfigurations on `app/Dockerfile` / compose (distroless `nonroot`, no root USER, no privileged flags).

### 1.4 CycloneDX SBOM

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${PWD}/submissions/lab9-artifacts:/out" \
  aquasec/trivy:0.59.1 image --format cyclonedx \
  --output /out/sbom-cyclonedx.json quicknotes:lab6
```

First 30 lines of [`sbom-cyclonedx.json`](lab9-artifacts/sbom-cyclonedx.json):

```json
{
  "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "serialNumber": "urn:uuid:faf04813-4bfd-49c7-a3d2-6c803ead66b4",
  "version": 1,
  "metadata": {
    "timestamp": "2026-10-05T08:20:10+00:00",
    "tools": {
      "components": [
        {
          "type": "application",
          "group": "aquasecurity",
          "name": "trivy",
          "version": "0.59.1"
        }
      ]
    },
    "component": {
      "bom-ref": "pkg:oci/quicknotes@sha256%3A8f415c9e22267b9017e96e00ee39ac25a09267650b8d813033ec56a06f726e00?arch=amd64&repository_url=index.docker.io%2Flibrary%2Fquicknotes",
      "type": "container",
      "name": "quicknotes:lab6",
```

### 1.5 Triage table — every HIGH/CRITICAL

| Finding | Sev | Source | Disposition | Reason |
|---------|-----|--------|-------------|--------|
| CVE-2026-25679 (stdlib / net/url) | HIGH | image (`quicknotes` + `healthcheck`) | **ACCEPT** | Fixed only in Go 1.25.8+/1.26.1+; course & Dockerfile pin Go 1.24. No IPv6 URL parsing in our handlers. Re-eval **2026-04-05**. |
| CVE-2026-27145 (crypto/x509 DoS) | HIGH | image | **ACCEPT** | TLS client-cert path unused (plain HTTP API). Re-eval **2026-04-05**. |
| CVE-2026-32280 (x509 chain DoS) | HIGH | image | **ACCEPT** | Same — no TLS termination in-process. Re-eval **2026-04-05**. |
| CVE-2026-32281 (x509 chain DoS) | HIGH | image | **ACCEPT** | Same. Re-eval **2026-04-05**. |
| CVE-2026-32283 (crypto/tls KeyUpdate) | HIGH | image | **ACCEPT** | No TLS server in QuickNotes. Re-eval **2026-04-05**. |
| CVE-2026-33811 (net CNAME DoS) | HIGH | image | **ACCEPT** | healthcheck dials fixed `http://127.0.0.1:8080`; no untrusted DNS. Re-eval **2026-04-05**. |
| CVE-2026-33814 (HTTP/2 SETTINGS) | HIGH | image | **ACCEPT** | App serves HTTP/1.1 on `:8080`; no HTTP/2 server configured. Re-eval **2026-04-05**. |
| CVE-2026-33818 (encoding/asn1) | HIGH | image | **ACCEPT** | No ASN.1/Unmarshal of untrusted certs. Re-eval **2026-04-05**. |
| CVE-2026-39820 (net/mail) | HIGH | image | **ACCEPT** | QuickNotes never parses email. Re-eval **2026-04-05**. |
| CVE-2026-39821 (idna / Punycode) | HIGH | image | **ACCEPT** | No IDNA hostname processing of client input. Re-eval **2026-04-05**. |
| CVE-2026-39822 (os.Root symlink) | HIGH | image | **ACCEPT** | App uses fixed `DATA_PATH`; not `os.Root` APIs. Re-eval **2026-04-05**. |
| CVE-2026-39836 (net NUL Dial) | HIGH | image | **ACCEPT** | No attacker-controlled Dial targets. Re-eval **2026-04-05**. |
| CVE-2026-42499 (net/mail) | HIGH | image | **ACCEPT** | Mail parsing unused. Re-eval **2026-04-05**. |
| CVE-2026-42504 (mime DoS) | HIGH | image | **ACCEPT** | API only sets `application/json`; no MIME multipart parsing. Re-eval **2026-04-05**. |
| CVE-2026-56853 (HTTP/2 cleartext DoS) | HIGH | image | **ACCEPT** | No h2c endpoint. Re-eval **2026-04-05**. |
| CVE-2026-56858 (html/template XSS) | HIGH | image | **ACCEPT** | API returns JSON only; no `html/template`. Re-eval **2026-04-05**. |
| CVE-2026-56859 (encoding/xml) | HIGH | image | **ACCEPT** | No XML decode path. Re-eval **2026-04-05**. |
| CVE-2026-56860 (net/url quadratic) | HIGH | image | **ACCEPT** | Request URLs are short mux patterns; Go `http.Server` already bounds headers. Re-eval **2026-04-05**. |
| CVE-2026-56862 (crypto/tls KeyUpdate) | HIGH | image | **ACCEPT** | No TLS. Re-eval **2026-04-05**. |
| AsymmetricPrivateKey `.vagrant/.../private_key` | HIGH | fs (secret) | **ACCEPT** | Local Vagrant SSH key for Lab 5 VM; **gitignored** (`.vagrant/` in `.gitignore`); not shipped in image/PR. Destroy with `vagrant destroy`. Re-eval **2026-04-05**. |

Config scan: **no HIGH/CRITICAL rows to triage**.

### Design questions (a–d)

**a)** Severity alone is not enough. Also weigh: **reachability** (is the vulnerable function on a request path?), **exploit maturity** (PoC / wormable?), **deployment context** (internet-facing vs localhost healthcheck; TLS or not), **data sensitivity**, and **compensating controls** (distroless, nonroot, network policy). A HIGH in unreachable `net/mail` on an API that never parses email is not the same as a HIGH in your auth parser.

**b)** Distroless removes shells, package managers, and most OS libraries — the attack surface for “break out and install tools / abuse libc CVEs” collapses. Trivy then mostly sees your binary’s stdlib, not hundreds of distro packages. Minimal base is the strongest single control because it deletes entire classes of findings instead of patching them forever.

**c)** `.trivyignore` is right when you have a **dated, written ACCEPT/WATCH** (ticket + re-eval date) and the finding is confirmed non-exploitable in *your* context. It is theater when used to silence scanners so CI stays green without a decision, owner, or expiry.

**d)** An SBOM lets you answer “do we ship Log4j / component X?” in minutes when the next Log4Shell-class advisory drops — inventory first, then patch — instead of grepping Dockerfiles and hoping you remember every transitive dependency.

---

## Task 2 — OWASP ZAP baseline + security-headers fix

Pinned scanner: **`ghcr.io/zaproxy/zaproxy:2.16.1`**. Target: `http://host.docker.internal:8080/health` (root `/` is 404 by design — no index route).

### 2.1 Before fix

Artifacts: [`zap-before/`](lab9-artifacts/zap-before/) (`zap-report.json`, `zap-report.html`, `zap-run.txt`).

```text
WARN-NEW: X-Content-Type-Options Header Missing [10021] x 1
	http://host.docker.internal:8080/health (200 OK)
WARN-NEW: Storable and Cacheable Content [10049] x 4
WARN-NEW: ZAP is Out of Date [10116] x 1
WARN-NEW: Insufficient Site Isolation Against Spectre Vulnerability [90004] x 1
	http://host.docker.internal:8080/health (200 OK)
FAIL-NEW: 0  WARN-NEW: 4  PASS: 63
```

### 2.2 ZAP triage

| ID | Name | Risk | URL | Disposition | Reason |
|----|------|------|-----|-------------|--------|
| 10021 | X-Content-Type-Options Header Missing | Low | `/health` | **FIX** | Added `X-Content-Type-Options: nosniff` via middleware (`app/security.go`). |
| 90004 | Insufficient Site Isolation Against Spectre | Low | `/health` | **FIX** | Added COOP/COEP/CORP headers in the same middleware. |
| 10049 | Storable and Cacheable Content → Non-Storable Content | Informational | `/health`, 404s | **ACCEPT** | After fix ZAP reports *Non-Storable* (we set `Cache-Control: no-store`). Correct for a JSON API. Re-eval **2026-04-05**. |
| 10116 | ZAP is Out of Date | Low | scan meta | **ACCEPT** | Scanner self-check against pinned `2.16.1`; not an app defect. Re-eval when bumping the ZAP image tag (≤ 6 months). |

### 2.3 Code fix (middleware + test)

`Routes()` returns `SecurityHeaders(mux)` so **every** route gets headers:

```go
// app/security.go
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		// ... CSP, COOP/COEP/CORP, Cache-Control: no-store ...
		next.ServeHTTP(w, r)
	})
}
```

Unit tests in [`app/security_test.go`](../app/security_test.go):
- `TestSecurityHeaders_PresentOnAllRoutes` — asserts `X-Content-Type-Options: nosniff` (and friends) on `/health`, `/notes`, `/metrics`
- `TestSecurityHeaders_FailsWithoutMiddleware` — bare mux lacks the header; `Routes()` has it (guards against removing the wrap)

`go test ./...` passes.

### 2.4 After fix (re-scan)

Rebuild: `docker build -t quicknotes:lab6 -f app/Dockerfile app` → recreate compose service.

Artifacts: [`zap-after/`](lab9-artifacts/zap-after/).

```text
PASS: Insufficient Site Isolation Against Spectre Vulnerability [90004]
...
WARN-NEW: Non-Storable Content [10049] x 4
WARN-NEW: ZAP is Out of Date [10116] x 1
FAIL-NEW: 0  WARN-NEW: 2  PASS: 65
```

**Proof:** plugin **10021** (`X-Content-Type-Options Header Missing`) is **gone** (now PASS). **90004** also PASS. Live headers:

```text
HTTP/1.1 200 OK
Cache-Control: no-store
Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
...
```

### Design questions (e–g)

**e)** Middleware guarantees one place, every route, including future handlers. Per-handler `Header().Set` drifts — someone adds `/admin` and forgets headers.

**f)** `default-src 'none'` blocks scripts, styles, images, fonts, frames. Fine for a pure JSON API with no browser UI. A real website would break (no JS/CSS) unless you allowlist origins.

**g)** Blind “accept all” buries the rare real issue in noise, teaches the team that findings don’t matter, and leaves no audit trail when something later becomes exploitable.

---

## Bonus — `govulncheck` CI PR gate

### Job (pinned)

Added to [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

```yaml
  govulncheck:
    runs-on: ubuntu-24.04
    defaults:
      run:
        working-directory: app
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/setup-go@0aaccfd150d50ccaeb58ebd88d36e91967a5f35b # v5.4.0
        with:
          go-version: '1.24'
      - name: install govulncheck (pinned)
        run: go install golang.org/x/vuln/cmd/govulncheck@v1.1.4
      - name: govulncheck ./...
        run: govulncheck ./...
```

`ci-ok` now `needs: [vet, test, lint, govulncheck]` so a red govulncheck blocks the PR.

### Red demo (deliberate bad dep) → green revert

Temporarily required `golang.org/x/net@v0.17.0` and called `http2.Framer.ReadFrame` ([`vuln_demo.go.red-demo`](lab9-artifacts/vuln_demo.go.red-demo)).

**Red** ([`govulncheck-red.txt`](lab9-artifacts/govulncheck-red.txt), exit 3):

```text
Vulnerability #1: GO-2024-2687
    HTTP/2 CONTINUATION flood in net/http
  Module: golang.org/x/net
    Found in: golang.org/x/net@v0.17.0
    Fixed in: golang.org/x/net@v0.23.0
Your code is affected by 1 vulnerability from 1 module.
```

**Green after revert** ([`govulncheck-green.txt`](lab9-artifacts/govulncheck-green.txt)):

```text
No vulnerabilities found.
```

(`app/go.mod` is back to module-only / Go 1.24; vuln demo file removed.)

### Design questions (h–j)

**h)** “Module has a CVE” means a dependency exists; “we don’t call the affected symbol” means your binary’s call graph never reaches the buggy function — so the practical exploit path is absent. Reachability cuts triage load: you prioritize **symbol-reachable** hits and can ACCEPT/WATCH package-only noise with evidence.

**i)** Pinning the scanner avoids silent behavior changes (new rules, exit codes, false-positive swings) when `@latest` moves — same reason we pin Trivy/ZAP image tags.

**j)** govulncheck won’t catch OS package CVEs, Dockerfile misconfig, secrets in the tree, or vulns in non-Go sidecars — Trivy image/fs/config (and ZAP for HTTP) cover those layers.

---

## How to reproduce (local)

```powershell
# Trivy
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.59.1 image --severity HIGH,CRITICAL quicknotes:lab6
docker run --rm -v "${PWD}:/src" -w /src aquasec/trivy:0.59.1 fs --severity HIGH,CRITICAL /src
docker run --rm -v "${PWD}:/src" -w /src aquasec/trivy:0.59.1 config --severity HIGH,CRITICAL /src

# App + ZAP
docker compose up -d quicknotes
docker run --rm -v "${PWD}/submissions/lab9-artifacts/zap-after:/zap/wrk:rw" -t `
  ghcr.io/zaproxy/zaproxy:2.16.1 zap-baseline.py -t http://host.docker.internal:8080/health -J zap-report.json -r zap-report.html -I

# Tests + govulncheck
cd app; go test ./...; go install golang.org/x/vuln/cmd/govulncheck@v1.1.4; govulncheck ./...
```
