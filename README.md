# OpenChoreo Skills

> **Supported OpenChoreo version: v1.0.0** — verified against v1.0.0 control plane, MCP servers, and `occ` CLI. Behaviour may differ on other versions.

Agent skills for working with [OpenChoreo](https://openchoreo.dev) — `SKILL.md` guides plus on-demand reference content that Claude Code (and other skill-compatible agents) load to install OpenChoreo, deploy applications, and operate the platform.

This repository is a fork of [lakwarus/openchoreo-skills](https://github.com/lakwarus/openchoreo-skills), itself extending the original [skills framework by Isala Piyarisi](https://github.com/isala404/openchoreo/tree/occ-skill/docs/skills). 

---

## Skills

Each skill is self-contained and can be installed independently.

- **[`openchoreo-install`](skills/openchoreo-install/SKILL.md)** — install OpenChoreo on a Kubernetes cluster (Colima, k3d, EKS, GKE, AKS, k3s, self-managed). Covers prerequisites, control plane, data plane, workflow plane, and observability plane.
- **[`openchoreo-developer`](skills/openchoreo-developer/SKILL.md)** — deploy and operate applications: BYOI, source builds, dependencies, secrets, per-environment overrides, promotion, debugging, alerts. Ships a 9-recipe library under `references/recipes/` covering each task end-to-end (MCP first, `occ` CLI fallback).
- **[`openchoreo-platform-engineer`](skills/openchoreo-platform-engineer/SKILL.md)** — author ComponentTypes, Traits, Workflows, AuthzRoles, and CEL templates. Diagnose plane-level failures.

---

## Install

Install all three skills:

```bash
npx skills add rashadism/skills-oc -g -y
```

Or just one — for example, the developer skill on its own:

```bash
npx skills add rashadism/skills-oc --skill openchoreo-developer -g -y
```

`-g` installs globally; `-y` skips prompts.

Then configure the OpenChoreo MCP servers (control plane + observer) per the official guide:

**https://openchoreo.dev/docs/ai/mcp-servers/**

| Server | Tool prefix | Purpose |
|---|---|---|
| `openchoreo-cp` | `mcp__openchoreo-cp__*` | Control plane: components, deployments, environments |
| `openchoreo-obs` | `mcp__openchoreo-obs__*` | Observer: logs, metrics, traces, alerts, incidents |

Once installed and MCP is configured, Claude Code activates the right skill automatically based on the task.

---

## Example prompts

```
Deploy my Node.js app in the current directory to OpenChoreo
```

```
Set up a new namespace with a dev and staging environment on OpenChoreo
```

```
Debug why my component is stuck in a pending state
```

```
Register a new ComponentType for a gRPC service
```

---

## Samples

End-to-end runs with prompts, transcripts, and results.

| Sample | What it demonstrates |
|---|---|
| [`samples/install-openchoreo-on-local-colima/`](samples/install-openchoreo-on-local-colima/README.md) | Fully automated OpenChoreo install on local macOS Colima from a single prompt — all planes, `openchoreo.localhost` domains, CoreDNS, ~6 minutes end-to-end |
| [`samples/google-microservice-demo/`](samples/google-microservice-demo/README.md) | Deploy the 12-service GCP Online Boutique onto OpenChoreo from a single prompt — BYOI, gRPC services, connections, external HTTP, worker type |

### Quick start — local Colima install

1. Install prerequisites: `brew install colima kubectl helm`
2. Add the install skill (see [Install](#install)).
3. Run Claude Code and paste:
   ```
   I want to try OpenChoreo on my local machine. I have Colima, kubectl, and
   Helm installed. Please set up a fresh OpenChoreo environment on my local
   Colima cluster using the openchoreo-install skill. Follow the
   local-colima.md guide and install everything: control plane, data plane,
   and workflow plane.
   ```

Claude Code handles the rest — ~6 minutes to a fully running cluster.
