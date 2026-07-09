# titan

Infrastructure-as-code for a home [Fedora CoreOS](https://fedoraproject.org/coreos/) (FCOS) [k3s](https://k3s.io/) cluster. Covers both node provisioning — Butane configs compiled to Ignition JSON and delivered at boot — and the Kubernetes workloads running on top.

All scripts must be run from the **repo root**. `butane`, `yq`, and `kubectl` run containerised via podman; there are no host-side tool dependencies beyond `make`, `podman`, and `jq`.

---

## Cluster Topology

| Node | Role | Hardware | OS |
|------|------|----------|----|
| `rick.expresso.lan` | k3s server | x86-64 bare-metal | Fedora CoreOS |
| `rpi4-0` | k3s agent | Raspberry Pi 4 | Fedora CoreOS |

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| `podman` | Runs containerised build tools (butane, yq, kubectl, nginx) and stores secrets |
| `make` | Primary task runner |
| `jq` | JSON processing (token generation, secretsdata output) |
| `git` (with submodule support) | Clone and keep submodules up to date |

After cloning, initialise submodules:

```bash
git submodule update --init --recursive
```

Submodules:
- `hack/vendor/bash-utils/` — bash utility library (logging, error constants)
- `hack/vendor/bashkit/` — additional bash toolkit

---

## Repository Layout

```
.
├── deploy/
│   ├── butane/          # Butane (.bu) source configs → compiled to Ignition JSON
│   │   ├── base/        # Shared FCOS config (containers, firewalld, sysctl, users…)
│   │   └── overlays/
│   │       ├── prod/    # x86 bare-metal node (rick.expresso.lan)
│   │       ├── staging/ # libvirt development VM (rick-dev)
│   │       └── rpi4/    # Raspberry Pi 4 agent node
│   ├── installer/       # Installer Makefile, downloaded FCOS ISOs, customised ISO variants
│   └── ansible/         # Post-boot node configuration for edge nodes
├── hack/
│   ├── bin/             # Executable scripts (ignition gen, token gen, manifest gen…)
│   ├── lib/             # Sourced shell libraries
│   └── env/             # Environment files for build tooling
├── pkg/
│   ├── operators/       # Kustomize + Helm configs for cluster operators
│   ├── workloads/       # Application deployments
│   ├── containers/      # Custom container image Containerfiles (with Makefile)
│   └── schemas/         # JSON value schemas for Helm chart validation
└── docs/                # Extended documentation
```

---

## Quickstart

### 1. Populate secrets env (first time only)

Copy the example file and fill in paths to your LUKS keyfiles and SSH public keys:

```bash
cp deploy/butane/base/secrets-example.env deploy/butane/overlays/prod/secrets.env
# Edit secrets.env: set SECRET_FILES to point at your keyfiles and SSH pubkeys
```

### 2. Generate k3s tokens (first time only)

Tokens are pre-generated and stored as podman secrets so they can be embedded into ignition configs for all nodes before any node boots.

```bash
make k3s-tokens-generate-prod
```

This creates podman secrets `k3s-token` and `k3s-token-agent`. Existing secrets are left unchanged with a warning; delete the secret manually to rotate.

### 3. Generate ignition for the production node

```bash
make ignition-gen-prod
```

This will:
1. Generate all Kubernetes manifests from `pkg/` via `kubectl kustomize --enable-helm`
2. Compile every `.bu` file referenced by `deploy/butane/overlays/prod/main.bu` through containerised `butane`
3. Validate the merged ignition JSON
4. Store the result as the podman secret `ignition-prod`

### 4. Serve ignition over HTTPS

```bash
# Generate self-signed TLS certs first (first time only)
make ignition-serve-gen-certs-prod

# Then serve
make ignition-serve-prod
```

Serves `ignition-prod` on ports 8080 and 8081 via a containerised nginx. Point the FCOS installer at `https://<build-host>:8081/config.ign` during PXE or ISO boot.

### 5. (Optional) Build a customised installer ISO

```bash
cd deploy/installer
make installer-ignition-gen-prod          # compiles install.bu → podman secret
make installer-iso-customize-prod         # embeds ignition into the downloaded FCOS ISO
```

---

## Make Targets Reference

Pass `XTRACE=1` to any root Makefile target to enable `set -x` shell tracing.

### Root `Makefile` — run as `make <target>` from repo root

#### Ignition Generation

| Target | Description |
|--------|-------------|
| `ignition-gen-prod` | Generate prod ignition (depends on all kube manifests + token gen) |
| `ignition-gen-staging` | Generate staging ignition (depends on staging kube manifests) |
| `ignition-gen-rpi4-0` | Generate RPi4 agent ignition |
| `ignition-gen-base` | Generate base ignition (depends on base kube manifests) |

Each target calls `hack/bin/ignition-gen-main.sh -b <path/to/main.bu> -s <overlay>` and stores the result as the podman secret `ignition-<overlay>`.

#### Ignition Serving

Serving targets require TLS secrets to be present. Generate them first with the corresponding `ignition-serve-gen-certs-*` target.

| Target | Description |
|--------|-------------|
| `ignition-serve-prod` | Serve prod ignition on ports 8080/8081 via nginx |
| `ignition-serve-staging` | Serve staging ignition via nginx (depends on gen + certs + tokens) |
| `ignition-serve-rpi4-0` | Serve RPi4 ignition via nginx (depends on gen + certs) |
| `ignition-serve-base` | Serve base ignition via nginx (depends on gen + certs + tokens) |
| `ignition-serve-gen-certs-prod` | Generate self-signed TLS key+cert for prod (stored as podman secrets) |
| `ignition-serve-gen-certs-staging` | Generate self-signed TLS key+cert for staging |
| `ignition-serve-gen-certs-rpi4-0` | Generate self-signed TLS key+cert for rpi4-0 |
| `ignition-serve-gen-certs-base` | Generate self-signed TLS key+cert for base |

#### Kubernetes Manifests

| Target | Description |
|--------|-------------|
| `kube-manifests-gen-prod` | Generate prod manifests |
| `kube-manifests-gen-staging` | Generate staging manifests |
| `kube-manifests-gen-base` | Generate base manifests |
| `kube-manifests-gen-all` | Clean and regenerate base + staging + prod manifests |
| `clean` | Remove all generated manifest YAML files |

Pass `DEBUG=1` to `kube-manifests-gen.sh` to enable `set -x` tracing in that script.

#### Tokens and Secrets

| Target | Description |
|--------|-------------|
| `k3s-tokens-generate-prod` | Generate `k3s-token` and `k3s-token-agent` podman secrets (prod) |
| `k3s-tokens-generate-staging` | Generate k3s token secrets (staging) |
| `k3s-tokens-generate-base` | Generate k3s token secrets (base) |

---

### `pkg/containers/Makefile` — run as `make -C pkg/containers <target>`

| Target | Description |
|--------|-------------|
| `container-build-ffmpeg` | Build custom FFmpeg image (x86-64, multi-stage) |
| `container-build-motion` | Build Motion detection image |
| `container-build-btrfs-progs` | Build btrfs-progs Alpine image |
| `container-build-envsubst` | Build envsubst image |
| `container-build-libcamera` | Build libcamera image (arm64) |
| `container-build-rpicam-apps` | Build rpicam-apps image (depends on libcamera) |
| `container-build-push-<name>` | Build and push image to `docker.io/steve51516` |

Optional env var overrides: `LIBCAMERA_VERSION_GIT_TAG_OVERRIDE`, `RPICAM_APPS_VERSION_TAG_OVERRIDE`.

---

### `deploy/installer/Makefile` — run as `make -C deploy/installer <target>`

| Target | Description |
|--------|-------------|
| `installer-download-baremetal` | Download latest stable FCOS ISO |
| `installer-download-libvirt` | Download latest FCOS qcow2 image for libvirt |
| `installer-ignition-gen-base` | Compile base installer ignition → podman secret |
| `installer-ignition-gen-prod` | Compile prod installer ignition → podman secret |
| `installer-ignition-gen-all` | Compile base + prod installer ignition configs |
| `installer-iso-customize-base` | Embed base ignition into ISO via coreos-installer |
| `installer-iso-customize-prod` | Embed prod ignition into ISO via coreos-installer |

---

## Ignition Generation Pipeline

Entry point: `hack/bin/ignition-gen-main.sh -b <main.bu> -s <secret_suffix>`

1. Calls `ignition_gen_config_merge_inlines` which parses `main.bu` via containerised `yq` (`docker.io/mikefarah/yq:4`), then iterates every `.ignition.config.merge[].inline` path.
2. For each referenced `.bu` file, runs containerised `butane` (`quay.io/coreos/butane:release`) with `--strict --files-dir=files`, mounting the `.bu` file's directory as `/data`.
3. Computes a `sha512` verification hash for each compiled inline.
4. Validates the fully merged config via `butane --check --strict`.
5. Stores the final ignition JSON as the podman secret `ignition-<secret_suffix>` (e.g. `ignition-prod`).

Key library files:

| File | Purpose |
|------|---------|
| `hack/lib/ignition/ignition.sh` | Core merge logic (`ignition_gen_config_merge_inlines`) |
| `hack/lib/ignition/butane.sh` | Podman wrapper for containerised butane; defines `__BUTANE_WORKDIR="/data"` |
| `hack/lib/ignition/serve.sh` | `serve()` function launching nginx for ignition serving |
| `hack/lib/podman/podman-secret.sh` | Secret create/inspect/filter helpers |
| `hack/lib/logging.sh` | Loads the bash-utils logging stack |

---

## Butane Config Structure

```
deploy/butane/
  base/               # Shared FCOS config (containers, firewalld, sysctl, users, btrfsmaintenance…)
  overlays/
    prod/             # Production x86 node ("rick.expresso.lan")
      main.bu         # Root config; lists all .bu files to merge under .ignition.config.merge[].inline
      secrets.env     # Declares SECRET_FILES array pointing to $HOME key files
      storage/        # disks.bu, filesystems.bu, luks.bu, raid.bu
    staging/          # Dev VM overlay (libvirt, VM name rick-dev)
    rpi4/             # Raspberry Pi 4 agent node
```

Prod storage layout:

- `root` — boot disk partition 4 (50 GiB), LUKS via TPM2 clevis, btrfs at `/`
- `var` — boot disk partition 5 (remaining), LUKS via keyfile, btrfs at `/var`
- `appdata` — 8 HDDs as mdadm RAID10 (`md-appdata`), LUKS via TPM2 + keyfile, btrfs at `/mnt/appdata`

---

## Kubernetes Manifests

`hack/bin/kube-manifests-gen.sh` finds all overlay directories matching the given overlay name under `pkg/`, runs `kubectl kustomize --enable-helm` on each, and writes `<app-name>.yaml` into the target manifests path. These generated YAML files are then embedded into the ignition config by butane.

Currently enabled apps (see `hack/env/kube-manifests-gen.env`):

**Operators:** `cert-manager`, `coredns-custom`, `intel-device-plugins-gpu`, `intel-device-plugins-operator`, `kube-vip`, `local-path-provisioner`, `mariadb-operator`, `mariadb-operator-crds`, `node-feature-discovery`, `traefik-custom`

**Workloads:** `jellyfin`, `mariadb-cluster`, `motion`, `v4l2rtspserver`

To enable or disable an app, edit the `apps_enabled` array in `hack/env/kube-manifests-gen.env`.

---

## k3s Token Generation

Entry point: `hack/bin/k3s-tokens-generate.sh -p <prefix>`

Tokens are pre-generated before any node boots and embedded into ignition configs so all server nodes share the same `K3S_TOKEN`. The script creates podman secrets `k3s-token` and `k3s-token-agent` (using `--ignore` to skip existing secrets), then produces `<prefix>-secrets.json` and `<prefix>-secretsdata.json` blobs stored as podman secrets. These JSON files use the podman file secret driver format and can be deployed to `/var/lib/containers/storage/secrets/filedriver/` on a remote host via ignition.

---

## Further Reading

- [Ignition Generation Pipeline](docs/ignition-pipeline.md) — how `.bu` files are compiled and merged
- [Storage Layout](docs/storage-layout.md) — RAID, LUKS, and btrfs configuration for the prod node
- [Kubernetes Operators and Workloads](docs/kubernetes.md) — what runs in the cluster
- [Networking](docs/networking.md) — physical LAN, podman networks, ingress, DNS, firewall
- [Node Provisioning](docs/node-provisioning.md) — end-to-end first-boot walkthrough

---

## Roadmap

- [ ] Simplify the staging libvirt environment
- [ ] GitHub Actions CI: lint and validate Quadlet container unit files
- [ ] CIS hardening for k3s ([guide](https://docs.k3s.io/security/hardening-guide))
- [ ] In-cluster container registry
