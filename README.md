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
| `podman` | Runs containerised build tools (butane, yq, kubectl, httpd) and stores secrets |
| `make` | Primary task runner |
| `jq` | JSON processing (token generation, secretsdata output) |
| `git` (with submodule support) | Clone and keep submodules up to date |

After cloning, initialise submodules:

```bash
git submodule update --init --recursive
```

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
│   │       └── rpi4-0/  # Raspberry Pi 4 agent node
│   ├── installer/       # Installer Makefile, downloaded FCOS ISOs, customised ISO variants
│   └── ansible/         # Post-boot node configuration for edge nodes
├── hack/
│   ├── bin/             # Executable scripts (ignition gen, token gen, httpd serve…)
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

### 1. Generate k3s tokens (first time only)

Tokens are pre-generated and stored as podman secrets so they can be embedded into ignition configs for all nodes before any node boots. See [docs/node-provisioning.md](docs/node-provisioning.md) for the reasoning.

```bash
make k3s-tokens-generate-prod
```

This creates podman secrets `k3s-token` and `k3s-agent-token`. If either already exists the script will warn and skip it; delete the secret first to rotate.

### 2. Generate ignition for the production node

```bash
make ignition-gen-prod
```

This will:
1. Generate all Kubernetes manifests from `pkg/` via `kubectl kustomize --enable-helm`
2. Compile every `.bu` file referenced by `deploy/butane/overlays/prod/main.bu` through containerised `butane`
3. Validate the merged ignition JSON
4. Store the result as the podman secret `prod-ignition`

> Requires `deploy/butane/overlays/prod/secrets.env` — copy and populate from `deploy/butane/base/secrets-example.env`. See [docs/examples/secrets-env.md](docs/examples/secrets-env.md).

### 3. Serve ignition over HTTP

```bash
make ignition-serve-httpd-prod
```

Serves the ignition config on port 8080 via a containerised httpd. Point the FCOS installer at `http://<build-host>:8080/ignition.json` during PXE or ISO boot.

### 4. (Optional) Build a customised installer ISO

```bash
make -C deploy/installer installer-ignition-gen-prod   # compiles install.bu → install.ign
make -C deploy/installer installer-iso-customize        # embeds ignition into the downloaded FCOS ISO
```

---

## Make Targets Reference

### Root `Makefile` — run as `make <target>` from repo root

#### Ignition

| Target | Description |
|--------|-------------|
| `ignition-gen-prod` | Generate prod ignition (depends on all kube manifests + token gen) |
| `ignition-gen-staging` | Generate staging ignition |
| `ignition-gen-rpi4-0` | Generate RPi4 agent ignition |
| `ignition-gen-base` | Generate base ignition (no overlay) |
| `ignition-serve-httpd-prod` | Serve prod ignition on port 8080 via httpd |
| `ignition-serve-nginx-prod` | Serve prod ignition on ports 8080/8081 via nginx (TLS) |
| `ignition-serve-httpd-staging` | Serve staging ignition via httpd |
| `ignition-serve-nginx-staging` | Serve staging ignition via nginx |
| `ignition-serve-httpd-rpi4-0` | Serve RPi4 ignition via httpd |
| `ignition-serve-nginx-rpi4-0` | Serve RPi4 ignition via nginx |
| `ignition-serve-httpd-base` | Serve base ignition via httpd |
| `ignition-serve-nginx-base` | Serve base ignition via nginx |

#### Kubernetes Manifests

| Target | Description |
|--------|-------------|
| `kube-manifests-gen-prod` | Generate prod + rpi4 manifests |
| `kube-manifests-gen-staging` | Generate staging manifests |
| `kube-manifests-gen-rpi4-0` | Generate rpi4 manifests |
| `kube-manifests-gen-base` | Generate base manifests |
| `kube-manifests-gen-all` | Clean and regenerate all overlays |
| `clean` | Remove all generated manifest YAML files |

#### Tokens & Secrets

| Target | Description |
|--------|-------------|
| `k3s-tokens-generate-prod` | Generate `k3s-token` and `k3s-agent-token` podman secrets |

Pass `XTRACE=1` to any root Makefile target to enable `set -x` shell tracing.

---

### `pkg/containers/Makefile` — run as `make -C pkg/containers <target>`

| Target | Description |
|--------|-------------|
| `container-build-ffmpeg` | Build custom FFmpeg image (x86-64, multi-stage) |
| `container-build-motion` | Build Motion detection image (depends on ffmpeg) |
| `container-build-btrfs-progs` | Build btrfs-progs Alpine image |
| `container-build-envsubst` | Build envsubst image (multi-arch: amd64 + arm64) |
| `container-build-libcamera` | Build libcamera image (arm64) |
| `container-build-rpicam-apps` | Build rpicam-apps image (depends on libcamera) |
| `container-tag-<name>` | Tag a built image with `latest` and remote registry tags |
| `container-push-<name>` | Push tagged image to `docker.io/steve51516` |
| `container-build-push-<name>` | Build, tag, and push in one step |

Optional env var overrides (set before the target): `LIBCAMERA_VERSION_GIT_TAG_OVERRIDE`, `RPICAM_APPS_VERSION_TAG_OVERRIDE`, `MOTION_VERSION_OVERRIDE`. See [docs/examples/container-build-env.md](docs/examples/container-build-env.md).

---

### `deploy/installer/Makefile` — run as `make -C deploy/installer <target>`

| Target | Description |
|--------|-------------|
| `installer-download-baremetal` | Download latest stable FCOS ISO to `deploy/installer/images/` |
| `installer-download-libvirt` | Download latest FCOS qcow2 image for libvirt |
| `installer-butane-check-base` | Validate base installer butane config |
| `installer-butane-check-prod` | Validate prod installer butane config |
| `installer-ignition-gen-base` | Compile base installer ignition → podman secret + SHA-512 |
| `installer-ignition-gen-prod` | Compile prod installer ignition |
| `installer-ignition-gen-all` | Compile all installer ignition configs |
| `installer-iso-customize` | Embed ignition into downloaded ISO via coreos-installer |

---

## Further Reading

- [Ignition Generation Pipeline](docs/ignition-pipeline.md) — how `.bu` files are compiled and merged
- [Storage Layout](docs/storage-layout.md) — RAID, LUKS, and btrfs configuration for the prod node
- [Kubernetes Operators & Workloads](docs/kubernetes.md) — what runs in the cluster
- [Networking](docs/networking.md) — physical LAN, podman networks, ingress, DNS, firewall
- [Node Provisioning](docs/node-provisioning.md) — end-to-end first-boot walkthrough
- [Examples: secrets-env.md](docs/examples/secrets-env.md) — how to configure `secrets.env`
- [Examples: container-build-env.md](docs/examples/container-build-env.md) — how to use container build env files

---

## Roadmap

- [ ] Simplify the staging libvirt environment
- [ ] GitHub Actions CI: lint and validate Quadlet container unit files
- [ ] CIS hardening for k3s ([guide](https://docs.k3s.io/security/hardening-guide))
- [ ] In-cluster container registry
