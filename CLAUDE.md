# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Infrastructure-as-code for a Fedora CoreOS (FCOS) k3s cluster. The two main concerns are:

1. **Node provisioning** — Butane configs compiled to Ignition JSON, delivered to FCOS nodes at boot
2. **Kubernetes workloads** — Kustomize + Helm manifests for operators and workloads running in k3s

All scripts must be run from the **repo root**. `butane`, `yq`, and `kubectl` run containerized via podman; there are no host-side dependencies for those tools beyond `make`, `podman`, and `jq`.

After cloning, initialize submodules:
```bash
git submodule update --init --recursive
```
Submodules: `hack/vendor/bashkit/` (github:s-fairchild/bashkit, standalone bash function library), `hack/vendor/bash-logger/` (github:s-fairchild/bash-logger, logging engine), and `deploy/butane/base/vendor/btrfsmaintenance/`. There is no `bash-utils` submodule — an earlier logging stack of that name was fully replaced by `bash-logger` (see below).

There is no automated test suite (no bats/shellcheck-CI). `.shellcheckrc` sets `external-sources=true source-path=SCRIPTDIR check-sourced=true`; validate a changed script with `shellcheck <file>` and by actually sourcing/running it from repo root.

## Key Make Targets

```bash
# Generate k3s tokens (run once before ignition gen; skips existing secrets with a warning)
make k3s-tokens-generate-prod

# Generate ignition configs (stores result as a podman secret)
make ignition-gen-prod          # depends on kube-manifests-gen-all + k3s-tokens-generate-prod
make ignition-gen-staging       # staging overlay
make ignition-gen-base          # base overlay
make ignition-gen-rpi4-0        # rpi4-0 agent overlay — currently BROKEN: depends on a
                                 # nonexistent `k3s-tokens-generate` target (only the
                                 # -base/-staging/-prod variants exist)

# Serve ignition over HTTPS after generating (requires the matching *-gen-certs-* target first)
make ignition-serve-gen-certs-prod
make ignition-serve-prod        # via podman-run nginx (TLS), ports 8080/8081

# Generate kube manifests only (runs kubectl kustomize --enable-helm)
make kube-manifests-gen-prod
make kube-manifests-gen-all     # clean + base + staging + prod

# Clean generated kube manifests
make clean

# Bring up / tear down the k3d + KubeVirt staging VM (see "Staging VM" below)
make staging-vm-up
make staging-vm-down

# Bring up / tear down the underlying k3d cluster itself (KubeVirt + CDI auto-installed)
make k3d-cluster-create-staging
make k3d-cluster-delete-staging
```

`XTRACE=1` enables `set -x` tracing on most `hack/bin/*.sh` entry points. `kube-manifests-gen.sh` and `podman-build.sh` use `DEBUG=1` instead. Verbosity for the bash-logger-backed scripts also honors `VERBOSE=1`/`QUIET=1` env vars, and several entry points additionally accept `-v`/`-q` CLI flags that take precedence over those env vars for that invocation (see "Logging" below).

Other Makefiles: `pkg/containers/Makefile` (run as `make -C pkg/containers <target>`, e.g. `container-build-push-ffmpeg`) and `deploy/installer/Makefile` (its own `Makefile`, see "Other Directories" below — note it still calls `ignition-gen-main.sh` with the older `-b`/`-n` flags, which no longer match that script's actual `-f`/`-p` getopts string; treat its ignition-gen targets as stale until fixed).

## First-Time Setup for prod Ignition

Before running `make ignition-gen-prod`, create and populate the secrets env (gitignored, no template is checked in):

```bash
$EDITOR deploy/butane/overlays/prod/secrets.env
# declare -ar SECRET_FILES=( ... )  # paths to LUKS keyfiles and SSH pubkeys
```

## Logging and Vendored Dependencies

All scripts source `hack/vendor/bash-logger-adapter/adapter.sh`, a compatibility shim that backs the *old* bash-utils logging API (`fatal`/`error`/`warn`/`info`/`debug`/`log`, the `ERROR_*`/`WARN_*` message constants, and `require_operands`) with the vendored `bash-logger` submodule (`hack/vendor/bash-logger/`). Every call site across `hack/lib`, `hack/bin`, and `hack/vendor/bashkit` is unchanged from the bash-utils days; only the sourcing path was repointed. Precedence for verbosity/quiet is **CLI flag > env var (`VERBOSE`/`QUIET`/`DEBUG`) > built-in default**; a script with its own `-v`/`-q` getopts flags calls `bash_logger_adapter_apply_overrides` after parsing to give the CLI tier priority.

`hack/vendor/bashkit/` is a standalone, independently-versioned library (its own `CLAUDE.md` at `hack/vendor/bashkit/CLAUDE.md` has full detail) vendored as a git submodule at exactly `hack/vendor/bashkit/`. Two different sourcing conventions are load-bearing and must not be mixed up:
- **Files inside `hack/vendor/bashkit/`** source their sibling dependencies (`bash-logger-adapter/adapter.sh`, `options.sh`) relative to their own location via `${BASH_SOURCE[0]%/*}/<relative-path>` — this lets `local/bin/*` wrapper executables (e.g. `coreos-installer`) run correctly regardless of the caller's CWD, including when installed standalone to `~/.local/bin`.
- **Every other consumer** (`hack/lib/*`, `hack/bin/*`) sources bashkit/bash-logger-adapter files with paths hardcoded relative to the **repo root** (e.g. `declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="local/lib/bashkit/options-operands-utils .sh"`), which is why those scripts must always be run from repo root.

Every sourced lib file (in both `hack/lib/` and `hack/vendor/bashkit/`) guards against double-inclusion with a `declare -r __<lib>_sourced="true"` check, and re-sources its own dependencies rather than assuming a caller already loaded them.

## Ignition Generation Pipeline

Entry point: `hack/bin/ignition-gen-main.sh -f <butane_main> -p <secret_suffix> [-s <secret_name>]... [-l <label>]... [-v] [-q] [-h]`
- `-f` — path to the root butane config (required)
- `-p` — suffix appended to `ignition-` for the resulting podman secret name, e.g. `-p prod` → `ignition-prod` (required)
- `-s` — podman secret name to mount into the butane container as a file under `files/secrets/<name>` (repeatable)
- `-l` — `key=value` label attached to the created secret (repeatable)

1. `ignition_gen_config_merge_inlines` (`hack/lib/ignition/ignition.sh`) parses the root `.bu` via containerized `yq`, then for every entry in `.ignition.config.merge[]`: reads its `inline` path, compiles that subordinate `.bu` file to ignition JSON via containerized `butane` (`ignition_gen()`), computes a `sha512-<hex>` verification hash of the compiled output, and writes both the inline JSON and `.verification.hash` back into the merge entry.
2. The fully merged document (all merge entries now inlined with verification hashes) is compiled once more through `butane --strict --files-dir=files` to produce the final ignition JSON, then that final JSON is logged with its byte size.
3. Stores the final ignition JSON as a podman secret named `ignition-<suffix>` via `podman_secret_create_replace_from_stdin` (uses `--replace`).

Key library files:
- `hack/lib/ignition/ignition.sh` — core merge/compile/hash logic (`ignition_gen`, `ignition_gen_config_merge_inlines`, `get_secrets_from_env`, `source_env_files`)
- `hack/lib/ignition/butane.sh` — podman wrapper for containerized butane; defines `__BUTANE_WORKDIR="/data"`
- `hack/lib/ignition/serve.sh` — `serve()` function driving nginx containers for ignition serving over HTTPS
- `hack/lib/podman/podman-secret.sh` — secret create/inspect/filter/showsecret helpers (`podman_secret_create_replace_from_stdin`, `podman_secret_create_from_file`, `podman_secret_gen_file_secretsdata`, `podman_secret_filter_by_label`)
- `hack/lib/podman/podman.sh` — umbrella loader for `podman-container.sh`, `podman-secret.sh`, `podman-volume.sh`
- `hack/lib/checksum/checksum.sh` — umbrella loader for `format.sh` (`checksum_parse_hash`) and `sha512sum.sh` (`sha512sum_gen`)
- `hack/vendor/bash-logger-adapter/adapter.sh` — logging shim described above

## Butane Config Structure

```
deploy/butane/
  base/               # shared FCOS config (containers, firewalld, sysctl, users, btrfsmaintenance…)
  overlays/
    prod/             # production x86 node ("rick.expresso.lan")
      main.bu         # root config; lists all .bu files to merge under .ignition.config.merge[].inline
      secrets.env     # declares SECRET_FILES array pointing to $HOME key files
      storage/        # disks.bu (partition layout), filesystems.bu (btrfs), luks.bu, raid.bu
      installer/      # install.bu — compiled separately via deploy/installer/Makefile
    staging/          # dev VM overlay (KubeVirt VM on a local k3d cluster, VM name rick-staging)
    rpi4-0/           # Raspberry Pi 4 agent node
```

Each `main.bu` is an FCOS butane config. Its `inline` entries under `.ignition.config.merge[]` are paths to other `.bu` files; the pipeline replaces each path with its compiled ignition JSON (plus a verification hash) before producing the final merged config.

Prod storage layout:
- `root` — boot disk partition 4 (50 GiB), LUKS via TPM2 clevis, btrfs at `/`
- `var` — boot disk partition 5 (remaining), LUKS via keyfile `secrets/var.keyfile.gz`, btrfs at `/var`
- `appdata` — 8 HDDs assembled as mdadm RAID10 (`md-appdata`, far2 layout, 6 active + 2 hot spares, 1024 chunk), LUKS via TPM2 + keyfile `secrets/appdata.keyfile.gz`, btrfs at `/mnt/appdata`

SSH keys are injected via `ssh_authorized_keys_local` referencing pubkey secrets created from `SECRET_FILES` in `secrets.env`.

## Kubernetes Manifests

`hack/bin/kube-manifests-gen.sh` finds directories under `pkg/` matching the given overlay name (`base`/`staging`/`prod`), runs `kustomize build` (`kubectl kustomize --enable-helm`-equivalent) on each, and writes `<app-name>.yaml` to the target manifests path (e.g. `deploy/butane/overlays/prod/files/usr/local/lib/rancher/k3s/server/manifests/custom/`). These generated YAML files are then embedded into the ignition config by butane.

App inclusion is controlled by `apps_enabled` in `hack/env/kube-manifests-gen.env` — **this is an allow-list matched as an ERE against the app's directory name** (`is_enabled()` in `kube-manifests-gen.sh` builds a `(app1|app2|...)` regex from it); an app not listed there is skipped even if its directory exists under `pkg/operators` or `pkg/workloads`. Currently enabled: `cert-manager`, `coredns-custom`, `intel-device-plugins-gpu`, `intel-device-plugins-operator`, `kube-vip`, `local-path-provisioner`, `mariadb-operator`, `mariadb-operator-crds`, `node-feature-discovery`, `traefik-custom`, `jellyfin`, `mariadb-cluster`, `motion`, `v4l2rtspserver`. `pihole` exists under `pkg/workloads/` but is commented out (disabled). To enable/disable an app, edit the `apps_enabled` array directly.

## k3s Token Generation

Entry point: `hack/bin/k3s-tokens-generate.sh -p <prefix> [-l <label>]... [-h]`
Library: `hack/lib/k3s/k3s-gen-token.sh`

Tokens are **pre-generated before any node boots** and embedded into ignition configs so all server nodes share the same `K3S_TOKEN`. Generating on first boot would require out-of-band coordination between nodes.

Creates podman secrets `k3s-token` and `k3s-token-agent` (skips existing secrets with a warning — delete manually to rotate), then produces `<prefix>-secrets.json` and `<prefix>-secretsdata.json` stored as podman secrets. These JSON files are consumed by the podman file secret driver and can be deployed to `/var/lib/containers/storage/secrets/filedriver/` on a remote host via ignition.

`k3s_gen_token()` tries `openssl rand -hex 32` (primary), falls back to `tr` then `shasum`/`sha256sum`. All produce 64 lowercase hex characters with no trailing newline — `podman_secret_create_replace_from_stdin` uses `printf '%s'` (not a here-string) to avoid a `\n` corrupting the stored token.

## Staging VM (k3d + KubeVirt)

Two clusters are involved and must not be conflated:
- **Outer cluster** — a local [k3d](https://k3d.io) cluster (config: `deploy/k3d/staging.yaml`, cluster name `kubevirt-staging`) hosting [KubeVirt](https://kubevirt.io) + CDI (Containerized Data Importer). This is what actually runs the FCOS guest as a `VirtualMachine` resource.
- **Inner cluster** — the k3s cluster that boots *inside* the FCOS guest via the normal ignition pipeline. This is unchanged by any of the above — still driven by `pkg/operators`/`pkg/workloads` + `apps_enabled` (see "Kubernetes Manifests").

`k3d`, `kubectl`, and `helm` are used as **host** binaries for this — unlike the containerized butane/yq/kubectl-kustomize used by the offline manifest pipeline, these commands manage/talk to a live cluster over the network, the same category of host tooling `virsh`/`virt-xml` used to be.

- `hack/bin/k3d-cluster-up.sh -f <k3d_config>` idempotently creates the k3d cluster (`k3d cluster create --config`, name read from `.metadata.name` via the containerized `yq()` wrapper) and installs KubeVirt + CDI via `hack/lib/kubevirt/kubevirt.sh` (`kubevirt_install`, `cdi_install`). `hack/bin/k3d-cluster-down.sh -f <k3d_config>` idempotently deletes it.
- KubeVirt (`v1.9.0`) and CDI (`v1.66.0`) are each defined as two flat `kustomization.yaml`s under `pkg/operators/{kubevirt,cdi}/{operator,cr}/`, each `resources:`-referencing the matching pinned upstream GitHub release URL — reusing the repo's normal kustomize-based operator pattern rather than raw `kubectl apply -f <url>`. `operator`/`cr` are separate kustomizations (not one) because the CR's CRD is only registered once the operator Deployment is running — `kubevirt_install`/`cdi_install` apply+wait on `operator` before applying `cr`. These are applied directly to the k3d/KubeVirt host cluster via `kubectl apply -k`, **not** picked up by `kube-manifests-gen.sh`/`apps_enabled` — deliberately flat (no `base`/`staging`/`prod` subdirectories anywhere under them) so its `find pkg -type d -name "$overlay"` traversal structurally can't match anything inside, keeping them out of any FCOS node's ignition-delivered k3s manifests.
- `hack/bin/kubevirt-vm-up.sh -f <vm.yaml> -n <namespace.yaml> -s <podman_ignition_secret>` applies the namespace, builds/applies a Kubernetes Secret (default name `ignition-payload`, key `userdata`) from the raw contents of the given podman secret (`podman_secret_showsecret "$secret" | jq -c`, matching `kubectl create secret generic ignition-payload --from-literal=userdata=...`), then applies the `VirtualMachine` manifest — its `cloudInitConfigDrive` volume references that Secret, which is how FCOS receives its ignition config under KubeVirt (no qemu fw_cfg involved). `hack/bin/kubevirt-vm-down.sh -f <vm.yaml>` deletes just the VM (`--ignore-not-found`); the k3d cluster and KubeVirt/CDI install are left running.
- `deploy/kubevirt/staging/vm.yaml` — the `VirtualMachine`: a registry-sourced `DataVolume` (CDI pulls `quay.io/fedora/fedora-coreos-kubevirt:stable`) for the OS disk, plus a masquerade-bound pod-network interface (KubeVirt's default NAT binding — the guest gets no LAN-routable IP; `deploy/butane/overlays/staging/files/etc/NetworkManager/system-connections/staging.nmconnection` is DHCP on `eth0` accordingly, not the static `192.168.150.10` the old passt setup used).
- Root `Makefile`: `staging-vm-up` (depends on `ignition-gen-staging` + `k3d-cluster-create-staging`) / `staging-vm-down` drive `kubevirt-vm-up.sh`/`kubevirt-vm-down.sh` against `deploy/kubevirt/staging/{vm,namespace}.yaml`. `k3d-cluster-create-staging`/`k3d-cluster-delete-staging` drive the outer cluster directly.
- `deploy/k3d/` is the common location for k3d cluster configs (`staging.yaml` today; a future `deploy/k3d/prod.yaml` + `k3d-cluster-create-prod`/`k3d-cluster-delete-prod` targets follow the same pattern, for running KubeVirt directly on the `rick` prod host once it's provisioned).

## Ignition Serving

`hack/lib/ignition/serve.sh` defines a `serve()` function that launches a containerized nginx server. The Makefile sources this file and calls `serve` with:
- `-i <ignition_secret>` — podman secret containing the ignition JSON to serve as `config.ign` (optional — omit when ignition is delivered some other way, as staging now does via its KubeVirt `cloudInitConfigDrive` instead of HTTP)
- `-c <ssl_cert>` / `-k <ssl_key>` — podman secret names for the TLS cert/key (required)
- `-s <secret>` — additional podman secret spec passed to `podman run --secret` (repeatable; prod passes the LUKS keyfiles and k3s secretsdata this way, staging passes just `staging-secrets.json`/`staging-secretsdata.json`)

The `ignition-serve-gen-certs-<overlay>` targets (`hack/bin/ignition-gen-serving-certs.sh`) generate a self-signed TLS key+cert (stored as podman secrets `ssl-key-<env>`/`ssl-cert-<env>`) before serving; they no-op with a warning if the secrets already exist.

## Other Directories

- `deploy/installer/` — own `Makefile`; downloads FCOS ISOs/qcow2 images and embeds ignition into them via `hack/vendor/bashkit/local/bin/coreos-installer` (podman wrapper) and `coreos-installer iso customize`. Several targets are commented out or reference stale paths (e.g. `hack/vendor/bashkit/lib/virsh/...` missing the `local/` segment) — verify a target actually runs before relying on it.
- `deploy/ansible/` — post-boot node configuration for edge nodes
- `deploy/k3d/` — k3d cluster configs (see "Staging VM" above)
- `deploy/kubevirt/` — per-overlay KubeVirt `VirtualMachine`/`Namespace` manifests (see "Staging VM" above)
- `pkg/containers/` — own `Makefile`; builds and pushes custom images (`ffmpeg`, `ffmpeg-rpi`, `motion`, `libcamera`, `rpicam-apps`, `envsubst`, `btrfs-progs`, `archlinuxarm`) to `docker.io/steve51516`
- `pkg/charts/` — vendored Helm chart sources; `pkg/schemas/` — JSON value schemas for Helm chart validation
- `docs/` — extended docs (`ignition-pipeline.md`, `storage-layout.md`, `kubernetes.md`, `networking.md`, `node-provisioning.md`); `docs/subagent-recommendations.md` recommends working directly from this file for Butane/Ignition/FCOS work rather than delegating to a generic infrastructure subagent, since none of the catalogued ones target FCOS specifically

## Overlays and Environments

| Overlay | Node type | Notes |
|---------|-----------|-------|
| `prod` | x86 bare-metal | hostname `rick.expresso.lan`, RAID10 + LUKS |
| `staging` | k3d + KubeVirt VM | dev cluster, VM name `rick-staging` |
| `rpi4-0` | Raspberry Pi 4 | k3s agent node |
