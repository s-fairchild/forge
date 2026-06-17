# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Infrastructure-as-code for a Fedora CoreOS (FCOS) k3s cluster. The two main concerns are:

1. **Node provisioning** — Butane configs compiled to Ignition JSON, delivered to FCOS nodes at boot
2. **Kubernetes workloads** — Kustomize + Helm manifests for operators and workloads running in k3s

All scripts must be run from the **repo root**. Both `butane` and `yq` run containerized via podman; there are no host-side dependencies for those tools beyond `make`, `podman`, and `jq`.

After cloning, initialise submodules (bash-utils lives under `hack/vendor/bash-utils/`):
```bash
git submodule update --init --recursive
```

## Key Make Targets

```bash
# Generate k3s tokens (run once before ignition gen; skips if secrets already exist)
make k3s-tokens-generate-prod

# Generate ignition configs (stores result as a podman secret)
make ignition-gen-prod          # prod overlay, reads deploy/butane/overlays/prod/secrets.env
make ignition-gen-staging       # staging overlay
make ignition-gen-base          # base overlay

# Serve ignition over HTTP (port 8080) after generating
make ignition-serve-http-prod

# Generate kube manifests (runs kubectl kustomize --enable-helm)
make kube-manifests-gen-prod    # also runs rpi4-0 as a dependency
make kube-manifests-gen-all     # clean + all overlays

# Clean generated kube manifests
make clean
```

`XTRACE=1` enables `set -x` tracing on any `make` target that passes it through. `VERBOSE=1` on `ignition-gen-prod` enables debug-level logging via the bash-utils `CONFIG[VERBOSE]` flag (sets debug output in `hack/vendor/bash-utils/util/logging.sh`). `kube-manifests-gen.sh` uses `DEBUG=true` instead of `XTRACE`.

## First-Time Setup for prod Ignition

Before running `make ignition-gen-prod`, copy and populate the secrets env:

```bash
cp deploy/butane/base/secrets-example.env deploy/butane/overlays/prod/secrets.env
# Edit secrets.env: fill in SECRET_FILES paths for LUKS keyfiles and SSH pubkeys
```

## Ignition Generation Pipeline

Entry point: `hack/bin/ignition-gen-main.sh <main.bu> [secrets.env]`

1. Sources `secrets.env` (if provided), which defines `SECRET_FILES` — an array of file paths for LUKS keyfiles and SSH public keys stored outside the repo (e.g. `$HOME/Documents/.luks_keys/*.keyfile.gz`). Optionally also defines `SECRET_IDS` for pre-existing podman secret IDs to mount.
2. Creates each file in `SECRET_FILES` as a named podman secret (`--ignore` skips existing).
3. Calls `ignition_gen_config_merge_inlines` which parses `main.bu` via containerized `yq` (`docker.io/mikefarah/yq:4.53.2`), then iterates every `.ignition.config.merge[].inline` path. For each referenced `.bu` file it runs containerized `butane` (`quay.io/coreos/butane:release`) with `--strict --raw --files-dir=files`, mounting the `.bu` file's directory as `/data` and secret files at `/data/files/secrets/`.
4. Validates the merged JSON via `butane --check --strict`.
5. Stores the final ignition JSON as a podman secret named `<overlay>-ignition` (e.g. `prod-ignition`) using `--replace`.

Key library files:
- `hack/lib/ignition/ignition.sh` — core logic (`ignition_gen_config_merge_inlines`)
- `hack/lib/ignition/butane.sh` — podman wrapper for containerized butane; defines `__BUTANE_WORKDIR="/data"`
- `hack/lib/podman/podman-secret.sh` — secret create/inspect/mount helpers
- `hack/lib/logging.sh` — loads the bash-utils logging stack (`hack/vendor/bash-utils/util/`)
- `hack/lib/vendor-bash-utils-logging.sh` — declares error message constants (`ERROR_ARG_REQUIRED`, `ERROR_FILE_NOT_FOUND`, etc.)

All library files use a `__<lib>_sourced` guard variable (e.g. `__ignition_sourced`, `__lib_podman_secret_sourced`) to prevent double-sourcing when included transitively.

## Butane Config Structure

```
deploy/butane/
  base/               # shared FCOS config (containers, firewalld, sysctl, users, btrfsmaintenance…)
  overlays/
    prod/             # production x86 node ("rick.expresso.lan")
      main.bu         # root config; lists all .bu files to merge under .ignition.config.merge[].inline
      secrets.env     # declares SECRET_FILES array pointing to $HOME key files
      storage/        # disks.bu (partition layout), filesystems.bu (btrfs), luks.bu, raid.bu
    staging/          # dev VM overlay
    rpi4-0/           # Raspberry Pi 4 agent node
```

Each `main.bu` is an FCOS butane v1.5.0 file. Its `inline` entries are paths to other `.bu` files; the pipeline replaces each path with its compiled ignition JSON before producing the final merged config.

Prod storage layout:
- `root` — boot disk partition 4 (50 GiB), LUKS via TPM2 clevis, btrfs at `/`
- `var` — boot disk partition 5 (remaining), LUKS via keyfile `secrets/var.keyfile.gz`, btrfs at `/var`
- `appdata` — 8 HDDs assembled as mdadm RAID10 (`md-appdata`, far2, 2 spares, 1024 chunk), LUKS via TPM2 + keyfile `secrets/appdata.keyfile.gz`, btrfs at `/mnt/appdata`

SSH keys are injected via `ssh_authorized_keys_local` referencing `secrets/id_ed25519_rick-root.pub` and `secrets/id_ed25519_rick-core.pub`, which come from the podman secrets created from `SECRET_FILES`.

## k3s Token Generation

Entry point: `hack/bin/k3s-tokens-generate.sh`  
Library: `hack/lib/k3s/k3s-gen-token.sh`

Tokens are **pre-generated before any node boots** and embedded into ignition configs so all server nodes share the same `K3S_TOKEN`. Generating on first boot would require out-of-band coordination between nodes.

`k3s_gen_token()` tries `openssl rand -hex 32` (primary), falls back to `tr` then `sha256sum`. All three produce 64 lowercase hex characters with no trailing newline.

`podman_secret_create_replace_from_stdin` in `hack/lib/podman/podman-secret.sh` uses `printf '%s'` (not a here-string) to pipe the value into `podman secret create` — a here-string (`<<<`) appends `\n`, which would corrupt the stored token and its base64 representation in `secretsdata.json`.

To inspect stored token values:
```bash
# Get JSON in podman file-driver secretsdata.json format
podman secret inspect --showsecret k3s-token k3s-agent-token \
  | jq 'map({(.ID): .SecretData}) | add'
```

Note: `podman secret inspect --format json` does **not** produce JSON — omit `--format` entirely to get JSON output.

`podman_secret_gen_file_secretsdata()` in `hack/lib/podman/podman-secret.sh` wraps the above for use in scripts.

## Kubernetes Manifests

```
pkg/
  operators/          # cert-manager, traefik, kube-vip, mariadb-operator, intel-device-plugins, …
  workloads/          # jellyfin, motion, mariadb-cluster, pihole, v4l2rtspserver
  charts/             # vendored Helm chart sources
  containers/         # Containerfiles for custom images (ffmpeg, motion, libcamera, envsubst…)
```

Each operator/workload follows the standard kustomize pattern: `base/kustomization.yaml` with overlay directories (`overlays/prod/`, `overlays/staging/`, etc.). Many use `--enable-helm` via `kubectl kustomize` with inline `HelmChart` or `HelmRelease` resources.

`hack/bin/kube-manifests-gen.sh` finds all `<overlay>` directories under `pkg/` using `find`, runs `kubectl kustomize --enable-helm` on each, and writes `<app-name>.yaml` to the target manifests path (e.g. `deploy/butane/overlays/prod/files/usr/local/lib/rancher/k3s/server/manifests/custom/`). These generated YAML files are then embedded into the ignition config by butane.

Apps can be excluded from manifest generation via the `disabled_pkgs` ERE pattern in `hack/env/kube-manifests-gen.env`. To disable an app, add its name to that file and include it in `disabled_pkgs`. Currently disabled: `pihole`, `coredns-custom`, `cloudnative-pg`, `cloudnative-pg-cluster`.

## Ignition Serving

After generation, `hack/bin/httpd-serve.sh <podman-secret-or-volume>` serves the ignition file over HTTP on port 8080 using a containerized `registry.access.redhat.com/hi/httpd` image. This is used to PXE/HTTP-boot FCOS nodes.

`hack/bin/ignition-gen-serving-certs.sh` generates a self-signed nginx TLS key and certificate (stored as podman secrets `nginx-ssl-private-key` and `nginx-ssl-certificate`) for use when serving ignition over HTTPS.

## Installer

`deploy/butane/overlays/prod/coreos-installer/install.bu` compiles to `install.ign`, which is embedded into the FCOS ISO via `coreos-installer iso customize`. The base installer ignition is gzip-compressed and sha512-verified before the prod layer references it (hash stored in `install.ign.sha512`).

## Overlays and Environments

| Overlay | Node type | Notes |
|---------|-----------|-------|
| `prod` | x86 bare-metal | hostname `rick.expresso.lan`, RAID10 + LUKS |
| `staging` | libvirt VM | dev cluster, VM name `rick-dev` |
| `rpi4-0` | Raspberry Pi 4 | k3s agent node |
