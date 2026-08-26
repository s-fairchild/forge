# Subagent Recommendations for Butane/Ignition/FCOS Work

Evaluation of the infrastructure subagents catalogued in [VoltAgent's `awesome-claude-code-subagents`](https://github.com/VoltAgent/awesome-claude-code-subagents/blob/main/categories/03-infrastructure/README.md) against the work this repo actually involves: Butane config authoring, the Ignition generation pipeline, and Fedora CoreOS (FCOS) node provisioning.

## Finding

**None of the 15 infrastructure subagents in that catalog target Butane/Ignition/FCOS directly.** That's a gap in the list — immutable-OS declarative provisioning is distinct from every category the README covers (cloud IaC, container orchestration, networking, databases, incident response). Routing Butane/Ignition-specific tasks to a subagent means relying on the agent's general shell/automation reasoning plus whatever `CLAUDE.md` context is loaded, not genuine FCOS domain training.

## Ranked Fit

| Agent | Fit | Why |
|---|---|---|
| **devops-engineer** | Best overall | The repo's `hack/bin`/`hack/lib` pipeline is bash automation wrapping containerized tools (`butane`, `yq`) and managing podman secrets to produce Ignition JSON — this is CI/CD-style automation tooling, the agent's core competency, even though it's never seen FCOS specifically. |
| **kubernetes-specialist** | Best for the other half | Covers `pkg/operators`/`pkg/workloads` — Kustomize + Helm manifests for the k3s side, which is a real Kubernetes domain this agent is built for. |
| **security-engineer** | Narrow but relevant | LUKS + Clevis/TPM2 disk encryption and secrets handling in the prod storage layout (`root`/`var`/`appdata`) touches its wheelhouse, though it's generic security rather than FCOS-aware. |
| **platform-engineer** | Weak/conceptual | The "golden path" framing (standardized node bootstrap via Ignition) loosely matches, but the agent has no FCOS-specific grounding to offer beyond generic platform philosophy. |
| **docker-expert** | Weak | Repo uses podman, not Docker — some container-build concepts transfer (multi-stage builds for `pkg/containers/`), but Butane/Ignition itself isn't containers. |

## Recommendation

- For anything touching `deploy/butane/`, `hack/lib/ignition/`, or the Ignition generation pipeline: prefer working directly with the `CLAUDE.md` pipeline docs already in context rather than delegating to a subagent.
- For the `pkg/` Kustomize/Helm side: `kubernetes-specialist` is a genuinely good fit if delegation is needed.
- If a subagent must be used for pipeline/tooling work, `devops-engineer` is the least-bad choice among the catalog.

## Full Catalog Reviewed

All 15 infrastructure subagents from the source README: `azure-infra-engineer`, `cloud-architect`, `database-administrator`, `docker-expert`, `deployment-engineer`, `devops-engineer`, `devops-incident-responder`, `incident-responder`, `kubernetes-specialist`, `network-engineer`, `platform-engineer`, `security-engineer`, `sre-engineer`, `terraform-engineer`, `terragrunt-expert`, `windows-infra-admin`.
