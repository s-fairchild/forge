# Example: `secrets.env`

`deploy/butane/base/secrets-example.env` is the template for the `secrets.env` file consumed by the ignition generation pipeline. It must exist — populated with real paths — before running `make ignition-gen-prod`.

---

## Step 1 — Copy the template

```bash
cp deploy/butane/base/secrets-example.env \
   deploy/butane/overlays/prod/secrets.env
```

The file is gitignored and must not be committed (it contains real paths to sensitive key material).

---

## Step 2 — Understand `SECRET_FILES`

`SECRET_FILES` is a bash array of host file paths or glob patterns. Each matched file is loaded into the podman secret store using its **basename** as the secret name. These secrets are mounted inside the butane container at `/data/files/secrets/` during ignition compilation, making them available to `.bu` file references of the form:

```yaml
# In a .bu file — references a file inside the butane container
contents:
  local: secrets/var.keyfile.gz
```

**Rules:**
- Glob patterns are expanded at runtime (e.g. `$HOME/.ssh/*_rick-root.pub`)
- If a secret with the same basename already exists in the podman store, it is **skipped** with a warning — delete it first to update
- Secrets are created with `--ignore` (idempotent)

**Typical entries:**

| Type | Example path | Basename (secret name) |
|------|-------------|------------------------|
| LUKS keyfile (var) | `$HOME/Documents/.luks_keys/var.keyfile.gz` | `var.keyfile.gz` |
| LUKS keyfile (appdata) | `$HOME/Documents/.luks_keys/appdata.keyfile.gz` | `appdata.keyfile.gz` |
| SSH public key (root) | `$HOME/.ssh/id_ed25519_rick-root.pub` | `id_ed25519_rick-root.pub` |
| SSH public key (core) | `$HOME/.ssh/id_ed25519_rick-core.pub` | `id_ed25519_rick-core.pub` |

---

## Step 3 — Understand `SECRET_IDS`

`SECRET_IDS` is a bash array of existing podman secret **names or IDs** that were already created outside this pipeline (e.g. by `make k3s-tokens-generate-prod`). The pipeline mounts them alongside `SECRET_FILES` secrets without re-creating them.

Use this for secrets that must be generated separately — such as k3s cluster tokens — and then referenced during ignition compilation:

```bash
# These must already exist in the podman secret store:
#   podman secret ls | grep k3s
SECRET_IDS=(
    "k3s-token"
    "k3s-agent-token"
    "prod-secretsdata.json"
)
```

The pipeline accepts both the 25-character secret ID and the human-readable name.

---

## Step 4 — Filled-out example

```bash
# deploy/butane/overlays/prod/secrets.env
# shellcheck shell=bash

declare -ar SECRET_FILES=(
    # LUKS keyfiles — gzip-compressed, stored outside the repo
    "$HOME/Documents/.luks_keys/var.keyfile.gz"
    "$HOME/Documents/.luks_keys/appdata.keyfile.gz"

    # SSH public keys for the root and core system users
    "$HOME/.ssh/id_ed25519_rick-root.pub"
    "$HOME/.ssh/id_ed25519_rick-core.pub"
)

declare -ar SECRET_IDS=(
    # k3s cluster tokens — created by make k3s-tokens-generate-prod
    "k3s-token"
    "k3s-agent-token"

    # secretsdata.json for the podman file secret driver on the remote node
    "prod-secretsdata.json"
)
```

---

## Step 5 — Verify secrets were created

After running `make ignition-gen-prod`, check that the expected secrets exist and carry the correct labels:

```bash
# List all secrets labelled for the prod config layer
podman secret ls --filter label=config=prod

# Show the raw content of a specific secret (for debugging only)
podman secret inspect --showsecret -f '{{.SecretData}}' var.keyfile.gz | xxd | head
```

---

## Step 6 — Rotating a secret

To replace a LUKS keyfile or SSH public key after it has been changed on disk:

```bash
# Remove the old secret
podman secret rm var.keyfile.gz

# Update the file on disk at the path declared in SECRET_FILES, then re-run
make ignition-gen-prod
```

The pipeline will recreate the secret from the updated file and regenerate the ignition config.

To rotate k3s tokens, see the [Rotating Secrets](../node-provisioning.md#rotating-secrets) section in `docs/node-provisioning.md`.
