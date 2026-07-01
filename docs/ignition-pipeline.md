# Ignition Generation Pipeline

Fedora CoreOS nodes are configured entirely at first boot via [Ignition](https://coreos.github.io/ignition/). This repo uses [Butane](https://coreos.github.io/butane/) as a human-readable source format; the pipeline compiles Butane configs to Ignition JSON and stores the result as a podman secret ready to serve.

All tools (`butane`, `yq`) run containerised via podman — no host-side installation required.

---

## Pipeline Overview

**Diagram key**

| Symbol | Meaning |
|---|---|
| Rectangle | Script / process |
| Rounded rectangle | Config file / data |
| Cylinder | Persistent secret / storage |
| Diamond | Decision |
| Parallelogram | Input / output |
| Circle | Endpoint |
| 🔵 Blue | Script or process |
| 🟢 Green | Storage / secret |
| 🔴 Red | Error / abort |
| 🟡 Amber | Decision |
| 🟣 Purple | Container image / tool |
| 🩵 Teal | Config / data file |

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    SECRETSENV[("fa:fa-key secrets.env\nSECRET_FILES · SECRET_IDS\nLUKS keyfiles · SSH pubkeys")]
    MAINBU[/"fa:fa-file-code main.bu\nFCOS Butane v1.7.0\n.ignition.config.merge[].inline"/]
    TOKENS[("fa:fa-key podman secrets\nk3s-token · k3s-agent-token")]

    subgraph STEP1["Step 1 — Create podman secrets from key files"]
        SECRET_CREATE["fa:fa-terminal podman secret create --ignore\nfor each file in SECRET_FILES\nNamed by basename"]
        SECRETS_STORE[("fa:fa-key podman secret store\nvar.keyfile.gz\nappdata.keyfile.gz\nid_ed25519_rick-root.pub\nid_ed25519_rick-core.pub")]
    end

    SECRETS_READY[("fa:fa-key Secrets ready\nmounted at /data/files/secrets/")]

    subgraph STEP2["Step 2 — Parse main.bu for inline paths"]
        YQ["fa:fa-cube containerised yq\ndocker.io/mikefarah/yq:4.53.2\nExtracts .ignition.config.merge[].inline"]
        INLINES[/"fa:fa-file-code List of .bu file paths"/]
    end

    subgraph STEP3["Step 3 — Compile each inline .bu → JSON"]
        LOOP{"for each\n.bu path"}
        BUTANE["fa:fa-cube containerised butane\nquay.io/coreos/butane:release\n--strict --raw --files-dir=files\nMount: .bu dir → /data"]
        FRAGMENT[/"fa:fa-file-code raw Ignition JSON fragment"/]
        REPLACE["fa:fa-terminal Replace inline path\nwith compiled JSON\nin main.bu"]
    end

    subgraph STEP4["Step 4 — Validate merged Ignition"]
        VALIDATE["fa:fa-cube butane --check --strict\nValidate full merged JSON"]
        VALID{"Valid?"}
        FAIL(["fa:fa-circle-xmark Fatal error\nAbort"])
    end

    subgraph STEP5["Step 5 — Store result"]
        STORE["fa:fa-terminal podman secret create --replace\nprod-ignition"]
        RESULT[("fa:fa-key podman secret\nprod-ignition\nFinal Ignition JSON")]
    end

    subgraph SERVE["Optional — Serve over HTTP"]
        HTTPD["fa:fa-wifi containerised httpd/nginx\nport 8080 · serve() in hack/lib/ignition/serve.sh"]
        NODE(["fa:fa-server FCOS node\nPXE / HTTP boot"])
    end

    SECRETSENV --> STEP1
    TOKENS --> STEP1
    STEP1 --> SECRET_CREATE
    SECRET_CREATE --> SECRETS_STORE
    SECRETS_STORE --> SECRETS_READY

    MAINBU --> STEP2
    STEP2 --> YQ
    YQ --> INLINES
    INLINES --> LOOP

    SECRETS_READY --> BUTANE
    LOOP -->|"each path"| BUTANE
    BUTANE --> FRAGMENT
    FRAGMENT --> REPLACE
    REPLACE -->|"next path"| LOOP
    REPLACE -->|"all done"| STEP4

    STEP4 --> VALIDATE
    VALIDATE --> VALID
    VALID -->|"no"| FAIL
    VALID -->|"yes"| STEP5
    STEP5 --> STORE
    STORE --> RESULT

    RESULT --> SERVE
    SERVE --> HTTPD
    HTTPD -->|"ignition.json\nHTTP :8080"| NODE

    style SECRETSENV fill:#15803d,stroke:#ccc,color:#fff
    style MAINBU fill:#0f766e,stroke:#ccc,color:#fff
    style TOKENS fill:#15803d,stroke:#ccc,color:#fff
    style SECRET_CREATE fill:#1d4ed8,stroke:#ccc,color:#fff
    style SECRETS_STORE fill:#15803d,stroke:#ccc,color:#fff
    style SECRETS_READY fill:#15803d,stroke:#ccc,color:#fff
    style YQ fill:#7e22ce,stroke:#ccc,color:#fff
    style INLINES fill:#0f766e,stroke:#ccc,color:#fff
    style LOOP fill:#b45309,stroke:#ccc,color:#fff
    style BUTANE fill:#7e22ce,stroke:#ccc,color:#fff
    style FRAGMENT fill:#0f766e,stroke:#ccc,color:#fff
    style REPLACE fill:#1d4ed8,stroke:#ccc,color:#fff
    style VALIDATE fill:#7e22ce,stroke:#ccc,color:#fff
    style VALID fill:#b45309,stroke:#ccc,color:#fff
    style FAIL fill:#b91c1c,stroke:#ccc,color:#fff
    style STORE fill:#1d4ed8,stroke:#ccc,color:#fff
    style RESULT fill:#15803d,stroke:#ccc,color:#fff
    style HTTPD fill:#7e22ce,stroke:#ccc,color:#fff
    style NODE fill:#1d4ed8,stroke:#ccc,color:#fff
```

---

## Entry Point

```
hack/bin/ignition-gen-main.sh <main.bu> [secrets.env]
```

Invoked by `make ignition-gen-<overlay>`. The prod overlay also passes `deploy/butane/overlays/prod/secrets.env`.

---

## Pipeline Steps

### Step 1 — Source secrets.env

If a `secrets.env` file is provided, it is sourced. It must define:

```bash
SECRET_FILES=(
    "$HOME/Documents/.luks_keys/var.keyfile.gz"
    "$HOME/Documents/.luks_keys/appdata.keyfile.gz"
    "$HOME/.ssh/id_ed25519_rick-root.pub"
    "$HOME/.ssh/id_ed25519_rick-core.pub"
)
SECRET_IDS=()   # optional: existing podman secret IDs to mount
```

See `deploy/butane/base/secrets-example.env` for a template and [docs/examples/secrets-env.md](examples/secrets-env.md) for a step-by-step guide.

### Step 2 — Create podman secrets from key files

Each path in `SECRET_FILES` becomes a podman secret named after its basename (e.g. `var.keyfile.gz`). The `--ignore` flag skips creation if the secret already exists, making the step idempotent.

### Step 3 — Parse main.bu and compile each inline

The pipeline uses containerised `yq` (`docker.io/mikefarah/yq:4.53.2`) to read every path under `.ignition.config.merge[].inline` in `main.bu`. For each path:

1. The directory containing the `.bu` file is mounted into the `butane` container as `/data`
2. All podman secrets are mounted at `/data/files/secrets/`
3. `butane --strict --raw --files-dir=files` compiles the `.bu` file to a raw Ignition JSON fragment
4. The path in `main.bu` is replaced with the compiled JSON

This is handled by `ignition_gen_config_merge_inlines` in `hack/lib/ignition/ignition.sh`.

The butane container image is `quay.io/coreos/butane:release`. The container working directory constant `__BUTANE_WORKDIR="/data"` is defined in `hack/lib/ignition/butane.sh`.

### Step 4 — Validate

The merged Ignition JSON is validated with `butane --check --strict` to catch any schema errors before storage.

### Step 5 — Store as podman secret

The final JSON is stored (with `--replace`) as a podman secret named `<overlay>-ignition`. The `make ignition-serve-httpd-<overlay>` and `make ignition-serve-nginx-<overlay>` targets read this secret and serve it via `serve()` in `hack/lib/ignition/serve.sh`.

---

## Butane Config Structure

```
deploy/butane/
├── base/                        # Shared config, merged into every overlay
│   ├── main.bu                  # Lists all base .bu files to merge
│   ├── btrfsmaintenance.bu
│   ├── etc-containers-systemd.bu
│   ├── etc-firewalld.bu
│   ├── etc-general.bu
│   ├── etc-security-limits.bu
│   ├── etc-sysctl.bu
│   ├── passwd.bu
│   ├── usr-local.bu
│   └── storage/
│       ├── disks.bu
│       └── filesystems.bu
└── overlays/
    ├── prod/                    # x86 bare-metal production node
    │   ├── main.bu              # Merges base + all prod-specific .bu files
    │   ├── secrets.env
    │   ├── etc-containers-secrets.bu
    │   ├── etc-containers-systemd.bu
    │   ├── etc-modprobe.bu
    │   ├── etc-sysconfig.bu
    │   ├── passwd.bu
    │   ├── usr-local.bu
    │   └── storage/
    │       ├── disks.bu         # Partition layout (50 GiB root + remaining var)
    │       ├── filesystems.bu   # btrfs volumes
    │       ├── luks.bu          # LUKS encryption config
    │       └── raid.bu          # mdadm RAID10 config
    ├── staging/                 # libvirt VM overlay
    └── rpi4-0/                  # Raspberry Pi 4 agent node
        ├── main.bu
        ├── storage.bu
        ├── system-config.bu
        └── usr.bu
```

Each `main.bu` is an FCOS Butane v1.7.0 file. The `inline` entries under `.ignition.config.merge` are file paths to other `.bu` files — the pipeline replaces each with its compiled Ignition JSON before producing the final merged config.

---

## Installer Ignition

The installer ignition is compiled separately for embedding into the FCOS ISO. Run from the `deploy/installer/` directory:

```bash
make -C deploy/installer installer-ignition-gen-base   # → install.ign podman secret + SHA-512
make -C deploy/installer installer-ignition-gen-prod   # compiles prod installer ignition
make -C deploy/installer installer-iso-customize        # embeds ignition into the downloaded ISO
```

The base ignition is stored as a podman secret along with its SHA-512 hash. The prod layer compiles `deploy/butane/overlays/prod/installer/install.bu` via the standard `ignition-gen-main.sh` pipeline.

**Diagram key** (same convention as the pipeline overview above)

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    BASE_BU[/"fa:fa-file-code deploy/butane/base/installer/install.bu"/]
    PROD_BU[/"fa:fa-file-code deploy/butane/overlays/prod/installer/install.bu"/]
    ISO_SRC[/"fa:fa-compact-disc FCOS live ISO\ndeploy/installer/images/\nvia installer-download-baremetal"/]

    subgraph BASE_GEN["installer-ignition-gen-base"]
        BUTANE_BASE["fa:fa-cube butane --strict\n--files-dir deploy/butane/base/installer"]
        IGN_SECRET[("fa:fa-key podman secret\ninstall.ign-base")]
        SHA_SECRET[("fa:fa-key podman secret\ninstall.ign.sha512-base")]
    end

    SECRETS_BOUNDARY[("fa:fa-key Base ignition secret\nand SHA-512 stored")]

    subgraph PROD_GEN["installer-ignition-gen-prod"]
        BUTANE_PROD["fa:fa-cube ignition-gen-main.sh\ndeploy/butane/overlays/prod/installer/install.bu"]
        PROD_IGN[("fa:fa-key podman secret\nprod-installer-ignition")]
    end

    subgraph ISO_GEN["installer-iso-customize"]
        CUSTOMIZE["fa:fa-terminal coreos-installer iso customize\nembeds ignition into ISO"]
        CUSTOM_ISO[("fa:fa-compact-disc custom.iso\nFCOS ISO with embedded ignition")]
    end

    BOOT(["fa:fa-server Boot target machine\nfrom USB / PXE"])

    BASE_BU --> BUTANE_BASE
    BUTANE_BASE --> IGN_SECRET
    BUTANE_BASE --> SHA_SECRET
    IGN_SECRET --> SECRETS_BOUNDARY
    SHA_SECRET --> SECRETS_BOUNDARY

    PROD_BU --> BUTANE_PROD
    SECRETS_BOUNDARY -.->|"reference"| BUTANE_PROD
    BUTANE_PROD --> PROD_IGN

    PROD_IGN --> CUSTOMIZE
    ISO_SRC --> CUSTOMIZE
    CUSTOMIZE --> CUSTOM_ISO
    CUSTOM_ISO -->|"dd to USB"| BOOT

    style BASE_BU fill:#0f766e,stroke:#ccc,color:#fff
    style PROD_BU fill:#0f766e,stroke:#ccc,color:#fff
    style ISO_SRC fill:#0f766e,stroke:#ccc,color:#fff
    style BUTANE_BASE fill:#7e22ce,stroke:#ccc,color:#fff
    style IGN_SECRET fill:#15803d,stroke:#ccc,color:#fff
    style SHA_SECRET fill:#15803d,stroke:#ccc,color:#fff
    style SECRETS_BOUNDARY fill:#15803d,stroke:#ccc,color:#fff
    style BUTANE_PROD fill:#7e22ce,stroke:#ccc,color:#fff
    style PROD_IGN fill:#15803d,stroke:#ccc,color:#fff
    style CUSTOMIZE fill:#1d4ed8,stroke:#ccc,color:#fff
    style CUSTOM_ISO fill:#15803d,stroke:#ccc,color:#fff
    style BOOT fill:#1d4ed8,stroke:#ccc,color:#fff
```

---

## Key Library Files

| File | Purpose |
|------|---------|
| `hack/lib/ignition/ignition.sh` | Core pipeline logic (`ignition_gen_config_merge_inlines`) |
| `hack/lib/ignition/butane.sh` | Podman wrapper for containerized butane; defines `__BUTANE_WORKDIR="/data"` |
| `hack/lib/ignition/serve.sh` | HTTP serving via nginx / httpd containers |
| `hack/lib/podman/podman-secret.sh` | Secret create/inspect/mount helpers |
| `hack/lib/checksum/checksum.sh` | SHA-512 hash generation and verification |
| `hack/lib/logging.sh` | Logging stack (loads `hack/vendor/bash-utils/util/`) |
| `hack/lib/vendor-bash-utils-logging.sh` | Error message constants (`ERROR_ARG_REQUIRED`, etc.) |
