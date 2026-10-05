# Lab 11 submission (bonus lab)

Author: Telman Nuruzov (`Telman3000`)
Branch: `feature/lab11`
Fork: https://github.com/Telman3000/DevOps-Intro

Course PR: https://github.com/inno-devops-labs/DevOps-Intro/pull/1729

---

## Layout

```text
flake.nix / flake.lock          # Nix flake (Go + deterministic OCI)
.github/workflows/nix-repro.yml # Bonus: two-job digest gate
scripts/lab11-nix-*.sh          # local build helpers (Docker nixos/nix)
submissions/lab11-artifacts/
```

Builds were run on Windows via `docker run nixos/nix` (two independent Nix store volumes = two environments).

---

## Task 1 — Reproducible Go build

### Why `buildGoModule`

QuickNotes is a plain Go module under `app/` with **no** third-party deps. `buildGoModule` is the nixpkgs-native builder (vendoring + `vendorHash` + Go toolchain pin). `buildGoApplication` (from `gomod2nix`) adds extra machinery we do not need here.

### `flake.nix` (packages + devShell)

See repo-root [`flake.nix`](../flake.nix). Highlights:

- `inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"` (+ committed [`flake.lock`](../flake.lock) rev `b6018f87…`)
- `buildGoModule.override { go = pkgs.go_1_24; }` — satisfies `go 1.24` in `app/go.mod`
- `env.CGO_ENABLED = "0"`, `ldflags = [ "-s" "-w" ]`
- `vendorHash = null` — required by nixpkgs when the vendor tree is empty (a pinned empty-tree hash is rejected)
- `devShell`: `go_1_24`, `gopls`, `golangci-lint`
- Outputs: `.#quicknotes`, `.#default`, `.#docker`

### Build log (excerpt)

```text
building '/nix/store/…-quicknotes-0.1.0.drv'...
Building subPackage .
Building subPackage ./cmd/healthcheck
ok  	quicknotes	0.008s
RESULT=/nix/store/zzqr90fjdgbimx33r194zwam2cilb90d-quicknotes-0.1.0
```

Full log: [`nix-build-quicknotes.txt`](lab11-artifacts/nix-build-quicknotes.txt)

### Two independent store hashes (identical)

| Env | How | `nix-store --query --hash` |
|-----|-----|----------------------------|
| A | `docker run -v nix-lab11-store:/nix nixos/nix` | `sha256:1p9a3f5340i7kqdrkx1a7q7zv40ky8g8llf5giq71gmzdgbh93lh` |
| B | `docker run -v nix-lab11-store-b:/nix nixos/nix` (fresh store) | `sha256:1p9a3f5340i7kqdrkx1a7q7zv40ky8g8llf5giq71gmzdgbh93lh` |

Artifacts: [`hash-env-a.txt`](lab11-artifacts/hash-env-a.txt), [`hash-env-b.txt`](lab11-artifacts/hash-env-b.txt)

### Runs /health

Loaded Nix OCI image (Task 2) and:

```text
$ curl -sS http://localhost:18080/health
{"notes":0,"status":"ok"}
```

(Binary is Linux ELF; exercised via `docker load` of `.#docker` rather than native Windows.)

### Design questions (a–d)

**a)** Plain `go build` embeds build IDs, often timestamps / VCS stamping, and resolves the toolchain & module cache from the ambient machine. Two laptops with “same Git SHA” can still differ in Go patch version, `GOROOT`, cgo, or file order — so bytes diverge.

**b)** `vendorHash` is the NAR hash of the **vendored module tree** Nix produces for the Go build. With dependencies it pins every module byte-for-byte. `vendorHash = null` skips that check and lets Nix fetch modules (or accept an empty vendor); for our zero-dep module nixpkgs **requires** `null`.

**c)** `flake.lock` pins nixpkgs (and every flake input) to exact revisions/narHashes. Delete it and the next eval may float to a newer `nixos-25.11` tip → different `go`, stdenv, `dockerTools` → different output hashes. The lockfile is the reproducibility contract.

**d)** `buildGoModule` = nixpkgs built-in. `buildGoApplication` = typically gomod2nix-generated, richer for large graphs. QuickNotes is tiny → `buildGoModule`.

---

## Task 2 — Deterministic OCI image

### Snippet

```nix
pkgs.dockerTools.buildImage {
  name = "quicknotes";
  tag = "nix";
  created = "1970-01-01T00:00:01Z";  # no wall-clock leak
  # copyToRoot: quicknotes + fakeNss + usrBinEnv + cacert
  config = {
    Entrypoint = [ "/bin/quicknotes" ];
    ExposedPorts = { "8080/tcp" = { }; };
    User = "65534:65534";  # nonroot
    Env = [ "ADDR=:8080" /* ... */ ];
  };
};
```

Built **without Docker daemon** (`nix build .#docker` only).

### Size comparison

| Image | Size |
|-------|-----:|
| Nix `quicknotes:nix` tarball | **~5.5 MB** (`quicknotes-nix.tar.gz`) |
| Lab 6 distroless `qn-lab6` | **~22.6 MB** |

### Two independent image digests (identical)

| Env | `sha256sum` of `result` (OCI tarball) |
|-----|----------------------------------------|
| A | `f0509f6538ae99412a8e37e086f50acaae72a1d54bf959f57d9298cc7299f8b0` |
| B | `f0509f6538ae99412a8e37e086f50acaae72a1d54bf959f57d9298cc7299f8b0` |

### Lab 6 `docker build --no-cache` twice — digests **differ**

```text
qn-lab6:run1 sha256:c7bf8ed7c1d95366dddb4c5b1af18f2d24d99716e20e74519d07547313ccb619 22.6MB
qn-lab6:run2 sha256:1806f7f065748cdbe7408b322b56c6f2198209b09793b71e4c494d7a2fbf81ec 22.6MB
```

([`lab6-digests.txt`](lab11-artifacts/lab6-digests.txt))

### Design questions (e–g)

**e)** `docker build` records layer timestamps, may pull floating base tags, and does not hash the entire build sandbox the way Nix does. Same Dockerfile + Git SHA still yields new layer IDs.

**f)** A signature proves *who attested this blob*. Reproducibility proves *anyone can regenerate that exact blob from source* — so a backdoored CI artifact that still has a valid signature would fail an independent rebuild check.

**g)** Nix costs learning curve, cold-build time, and niche ecosystem friction. `docker build` is universal, cached in every team’s muscle memory, and “good enough” until supply-chain policy demands bit-identity.

---

## Bonus — CI-verified reproducibility

Workflow: [`.github/workflows/nix-repro.yml`](../.github/workflows/nix-repro.yml)

- Triggers: `push`, `pull_request`, `workflow_dispatch`
- Jobs `repro-a` / `repro-b` (parallel fresh runners) → `nix build .#docker` → digest outputs
- Job `compare` fails if digests differ
- Nix installer pinned: `DeterminateSystems/nix-installer-action@e50d5f73…` (v16)

### Red demo

Two ways (GitHub hides **Run workflow** until `workflow_dispatch` exists on the fork’s **default** branch):

1. **Branch trigger (recommended here):** push `feature/lab11-break` — job `repro-a` patches `created=`, `compare` goes red.
2. **workflow_dispatch:** after merging the workflow to `main`, Actions → nix-repro → Run workflow → `break_repro=true`.

### Green / red run URLs

_(fill after first CI runs on `feature/lab11`)_

| Run | URL |
|-----|-----|
| Green (match) | https://github.com/Telman3000/DevOps-Intro/actions/runs/37294579076 |
| Red (`feature/lab11-break`) | https://github.com/Telman3000/DevOps-Intro/actions/runs/37295319676 |

### Design questions (h–j)

**h)** Laptop proof is anecdotal and under your control. CI on two fresh VMs is an **independent, auditable, repeatable** gate a security reviewer can re-run without trusting your laptop.

**i)** One job building twice can share a poisoned local store / impure env between runs. Two parallel runners force separate machines/stores.

**j)** Timestamps normally leak via image `created`, Go buildinfo, or file mtimes. We pin `created = "1970-01-01T00:00:01Z"`; `dockerTools` then does not consult wall-clock / `SOURCE_DATE_EPOCH` for that field. The red demo flips `created` to show how a timestamp leak breaks the digest.

---

## How to finish

1. Commit `flake.nix`, `flake.lock`, workflow, `submissions/lab11*` (**you** push)
2. Open PR `feature/lab11` → course `main`
3. After green Actions: `workflow_dispatch` with **break_repro** for red evidence; paste URLs above
4. Moodle
