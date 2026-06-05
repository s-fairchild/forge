# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Infrastructure-as-code for a Fedora CoreOS (FCOS) k3s cluster. The two main concerns are:

1. **Node provisioning** — Butane configs compiled to Ignition JSON, delivered to FCOS nodes at boot
2. **Kubernetes workloads** — Kustomize + Helm manifests for operators and workloads running in k3s

All scripts must be run from the **repo root**. Both `butane` and `yq` run containerized via podman; there are no host-side dependencies for those tools.

## Key Make Targets

```bash
# Generate ignition configs (stores result as a podman secret)
make ignition-gen-prod          # prod overlay, reads deploy/butane/overlays/prod/secrets.env
make ignition-gen-staging       # staging overlay
make ignition-gen-base          # base overlay

# Serve ignition over HTTP (port 8080) after generating
make ignition-serve-http-prod

# Generate kube manifests (runs kubectl kustomize --enable-helm)
make kube-manifests-gen-prod    # also runs rpi4-0 as a dependency
make kube-manifests-gen-all     # clean + all overlays

# Installer ISO
make installer-ignition-gen-prod     # compiles install.bu to install.ign with hash verification
make installer-iso-customize         # embeds ignition into a downloaded FCOS ISO

# Container images
make container-build-ffmpeg
make container-build-motion
make container-build-envsubst

# Clean generated kube manifests
make clean
```

`XTRACE=true` enables `set -x` tracing on any `make` target that passes it through. `VERBOSE` is also forwarded for `ignition-gen-prod`.

## Ignition Generation Pipeline

Entry point: `hack/bin/ignition-gen-main.sh <main.bu> [secrets.env]`

1. Sources `secrets.env` (if provided), which defines `SECRET_KEYS` — an array of file paths/globs for LUKS keyfiles and SSH public keys stored outside the repo (e.g. `$HOME/Documents/.luks_keys/*.keyfile.gz`).
2. Creates each file in `SECRET_KEYS` as a named podman secret (`--ignore` skips existing).
3. Calls `ignition_gen_config_merge_inlines` which parses the `main.bu` via containerized `yq` (`docker.io/mikefarah/yq:4.53.2`), then iterates every `.ignition.config.merge[].inline` path. For each referenced `.bu` file it runs containerized `butane` (`quay.io/coreos/butane:release`) with `--strict --raw --files-dir=files`, mounting the `.bu` file's directory as `/data` and secret files at `/data/files/secrets/`.
4. Validates the merged JSON via `butane -cs`.
5. Stores the final ignition JSON as a podman secret named `<overlay>-ignition` (e.g. `prod-ignition`) using `--replace`.

Key library files under `hack/lib/ignition/`: `ignition.sh` (core logic), `butane.sh` (podman wrapper), `constants.env` (`__BUTANE_WORKDIR="/data"`). Secret helpers are in `hack/lib/podman/podman-secret.sh`. Logging/error constants come from `hack/lib/opt-bash-utils-logging.sh` (which loads `hack/opt/bash-utils/` — a git submodule).

## Butane Config Structure

```
deploy/butane/
  base/               # shared FCOS config (containers, firewalld, sysctl, users, btrfsmaintenance…)
  overlays/
    prod/             # production x86 node ("rick.expresso.lan")
      main.bu         # root config; lists all .bu files to merge under .ignition.config.merge[].inline
      secrets.env     # declares SECRET_KEYS array pointing to $HOME key files
      storage/        # disks.bu (partition layout), filesystems.bu (btrfs), luks.bu, raid.bu
    staging/          # dev VM overlay
    rpi4-0/           # Raspberry Pi 4 agent node
```

Each `main.bu` is an FCOS butane v1.5.0 file. Its `inline` entries are paths to other `.bu` files; the pipeline replaces each path with its compiled ignition JSON before producing the final merged config.

Prod storage layout:
- `root` — boot disk partition 4 (50 GiB), LUKS via TPM2 clevis, btrfs at `/`
- `var` — boot disk partition 5 (remaining), LUKS via keyfile `secrets/var.keyfile.gz`, btrfs at `/var`
- `appdata` — 8 HDDs assembled as mdadm RAID10 (`md-appdata`, far2, 2 spares, 1024 chunk), LUKS via TPM2 + keyfile `secrets/appdata.keyfile.gz`, btrfs at `/mnt/appdata`

SSH keys are injected via `ssh_authorized_keys_local` referencing `secrets/id_ed25519_rick-root.pub` and `secrets/id_ed25519_rick-core.pub`, which come from the podman secrets created from `SECRET_KEYS`.

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

## Ignition Serving

After generation, `hack/bin/httpd-serve.sh <podman-secret-or-volume>` serves the ignition file over HTTP on port 8080 using a containerized `registry.access.redhat.com/hi/httpd` image. This is used to PXE/HTTP-boot FCOS nodes.

## Installer

`deploy/butane/overlays/prod/coreos-installer/install.bu` compiles to `install.ign`, which is embedded into the FCOS ISO via `coreos-installer iso customize`. The base installer ignition is gzip-compressed and sha512-verified before the prod layer references it (hash stored in `install.ign.sha512`).

## Overlays and Environments

| Overlay | Node type | Notes |
|---------|-----------|-------|
| `prod` | x86 bare-metal | hostname `rick.expresso.lan`, RAID10 + LUKS |
| `staging` | libvirt VM | dev cluster, VM name `rick-dev` |
| `rpi4-0` | Raspberry Pi 4 | k3s agent node |
