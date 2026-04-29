# OpenChoreo Skills

> **Supported OpenChoreo version: v1.0.0**
> The skills, reference files, and MCP tool mappings in this repository are verified against OpenChoreo **v1.0.0**. Behaviour may differ on earlier or later versions.

This repository contains **OpenChoreo Skills** — structured guides and reference documentation that AI agents (such as Claude Code) and automation tools use to operate on the OpenChoreo internal developer platform.

Each skill is a directory with a `SKILL.md` that tells an AI agent how to work in that role, and a `references/` directory with detailed topic files the agent reads on demand.

---

## Acknowledgement

The original OpenChoreo skills framework was created by **Isala Piyarisi** and is available here:

https://github.com/isala404/openchoreo/tree/occ-skill/docs/skills

This repository builds on that work and extends it with additional reference documentation, MCP tool guides, and platform engineer coverage.

Special thanks to Isala for creating the initial developer skills foundation.

---

## Quick start — install OpenChoreo on local Colima

Want to get OpenChoreo running on your Mac in one prompt? See the [local Colima install sample](samples/install-openchoreo-on-local-colima/README.md):

1. Install prerequisites: `brew install colima kubectl helm`
2. Add the install skill to Claude Code: `claude skills add https://github.com/lakwarus/openchoreo-skills/tree/main/openchoreo-install -g`
3. Run Claude Code and paste:
   ```
   I want to try OpenChoreo on my local machine. I have Colima, kubectl, and
   Helm installed. Please set up a fresh OpenChoreo environment on my local
   Colima cluster using the openchoreo-install skill. Follow the
   local-colima.md guide and install everything: control plane, data plane,
   and workflow plane.
   ```

Claude Code handles the rest — ~6 minutes to a fully running cluster.

---

## Skills in this repository

Each skill is self-contained and includes the foundational `concepts.md`, `cli.md`, `mcp.md`, and `resource-schemas.md` references — install any skill standalone without needing the others.

**Foundational references shipped in every skill:**

| File | Contents |
|------|----------|
| `concepts.md` | Resource hierarchy, abstractions, cell architecture, planes |
| `cli.md` | `occ` install, login, context, command surface, universal gotchas |
| `mcp.md` | Control-plane and observability MCP tool catalog, exploration workflow |
| `resource-schemas.md` | YAML shapes for Project, Component, Workload, Workload Descriptor, Environment, DeploymentPipeline, ReleaseBinding, SecretReference |

---

### `openchoreo-developer`

For application-level work: deploying apps, debugging Components and Workloads, writing app-facing YAML, and operating through `occ` or the MCP server.

**Skill-specific references:**

| File | Contents |
|------|----------|
| `deployment-guide.md` | BYOI, source builds, `workload.yaml`, dependencies, promotion, env vars / config / secrets, third-party apps walkthrough |

---

### `openchoreo-platform-engineer`

For platform-level work: cluster setup, Helm, kubectl, planes, ComponentTypes, Traits, Workflows, gateways, secret stores, and observability.

**Skill-specific references:**

| File | Contents |
|------|----------|
| `component-types-and-traits.md` | ComponentType, ClusterComponentType, Trait, ClusterTrait authoring (schema, templates, patches, validation) |
| `workflows.md` | Workflow / ClusterWorkflow authoring (schema, runTemplate, ClusterWorkflowTemplates, CI governance) |
| `cel.md` | CEL syntax, context variables, OpenChoreo built-in & helper functions used in all template authoring |
| `authz.md` | AuthzRole / RoleBinding authoring, action catalogue, evaluation rules |
| `troubleshooting.md` | Failure isolation, health checks, common patterns |

For platform setup and configuration (TLS, registries, identity providers, multi-cluster connectivity, GitOps, observability stack install, modules, upgrades, namespace management, Backstage), the skill points at the official [PE guide](https://openchoreo.dev/docs/platform-engineer-guide/).

---

## Using with Claude Code

Claude Code supports loading external skill repositories as custom skills. When configured, Claude Code reads the `SKILL.md` files in this repository and uses them to guide its behaviour when working with OpenChoreo.

### Step 1 — Add this repository as a skill source

Run the following command to install both skills globally:

```bash
npx skills add https://github.com/lakwarus/openchoreo-skills/blob/main/README.md -g -y
```

- `-g` installs globally (available in all projects)
- `-y` skips confirmation prompts

### Step 2 — Configure the OpenChoreo MCP server

Both skills use two MCP servers:

| Server | Tool prefix | Purpose |
|--------|------------|---------|
| `openchoreo-cp` | `mcp__openchoreo-cp__*` | Control plane — manage components, deployments, environments |
| `openchoreo-obs` | `mcp__openchoreo-obs__*` | Observer API — query logs, metrics, and traces |

Follow the official configuration guide to register both:

**https://openchoreo.dev/docs/reference/mcp-servers/mcp-ai-configuration/**

### Step 3 — Use the skills

Once configured, Claude Code will automatically activate the relevant skill based on your task:

- Tasks about deploying apps, debugging components, or writing YAML → `openchoreo-developer` activates
- Tasks about cluster setup, plane registration, ComponentTypes, or platform config → `openchoreo-platform-engineer` activates
- Tasks that cross both boundaries → both skills activate together

**Example prompts:**

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

### Using with other AI tools

Any AI tool or agent that supports the Claude skills / MCP skill model can use this repository. Point the tool at this repository root and load the `SKILL.md` for the relevant role. The `references/` files are loaded on demand by the skill routing rules in each `SKILL.md`.

For **Cursor**, **Windsurf**, or other editors with MCP support, configure the OpenChoreo MCP server as above and reference the `SKILL.md` files directly in your system prompt or context window.

---

## Samples

The `samples/` directory contains end-to-end examples showing how to use these skills with real applications.

| Sample | What it demonstrates |
|--------|---------------------|
| [`samples/install-openchoreo-on-local-colima/`](samples/install-openchoreo-on-local-colima/README.md) | Fully automated OpenChoreo install on local macOS Colima from a single prompt — all planes, `openchoreo.localhost` domains, CoreDNS, ~6 minutes end-to-end |
| [`samples/google-microservice-demo/`](samples/google-microservice-demo/README.md) | Deploy the 12-service GCP Online Boutique onto OpenChoreo using a single prompt — BYOI, gRPC services, connections, external HTTP, worker type |

Each sample includes the exact prompt used, a step-by-step account of what the AI did, results, and any issues discovered.

---

## Repository structure

Every skill ships the four foundational references (`concepts.md`, `cli.md`, `mcp.md`, `resource-schemas.md`) plus its own skill-specific references, so any skill can be installed standalone.

```
openchoreo-install/
  SKILL.md                  # Install skill guide — loaded by AI agent
  references/
    concepts.md             # Resource model, cell architecture, planes
    cli.md                  # occ install, login, command surface, universal gotchas
    mcp.md                  # MCP tool catalog (control plane + observability)
    resource-schemas.md     # Universal YAML shapes
    local-colima.md         # Colima/k3s install path (openchoreo.localhost)
    local-k3d.md            # k3d install path
    prerequisites.md        # Tool versions, CRDs, cert-manager, kgateway, OpenBao
    control-plane.md        # TLS, Helm install, Thunder, domain config
    data-plane.md           # Data plane install and ClusterDataPlane registration
    workflow-plane.md       # Workflow plane install and ClusterWorkflowPlane
    observability-plane.md  # Observability plane install
    cleanup.md              # Full uninstall sequence

openchoreo-developer/
  SKILL.md                  # Developer skill guide — loaded by AI agent
  references/
    concepts.md             # Resource model, cell architecture, planes
    cli.md                  # occ install, login, command surface, universal gotchas
    mcp.md                  # MCP tool catalog (control plane + observability)
    resource-schemas.md     # Universal YAML shapes
    deployment-guide.md     # BYOI, source builds, workload.yaml, dependencies, promotion, third-party apps

openchoreo-platform-engineer/
  SKILL.md                  # Platform engineer skill guide — loaded by AI agent
  references/
    concepts.md                    # Resource model, cell architecture, planes
    cli.md                         # occ install, login, command surface, universal gotchas
    mcp.md                         # MCP tool catalog (control plane + observability)
    resource-schemas.md            # Universal YAML shapes
    component-types-and-traits.md  # ComponentType / Trait authoring
    workflows.md                   # Workflow authoring + CI governance
    cel.md                         # CEL syntax, context variables, helpers
    authz.md                       # AuthzRole / RoleBinding authoring
    troubleshooting.md             # Failure isolation, health checks, common patterns

samples/
  install-openchoreo-on-local-colima/
    README.md               # Prerequisites, skill setup, prompt, step-by-step run, results
  google-microservice-demo/
    README.md               # Prompt, mapping plan, results, known issues
```

---

## Use cases

- AI agents automating developer workflows on OpenChoreo
- Self-service developer portals backed by an AI agent
- Platform engineering automation via MCP
- CI/CD and GitOps integrations
- Migrating existing Kubernetes workloads into OpenChoreo-managed components
- Onboarding legacy services into OpenChoreo through conversational AI

---

## Contributing

Contributions are welcome.

You can:

- Add new reference files
- Improve existing skills or references
- Add examples
- Improve the MCP tool guides

Please keep the progressive-discovery pattern: `SKILL.md` stays lean and routes to references rather than duplicating content.

---

## License

Same license as OpenChoreo / original skills unless stated otherwise.

---

## Maintainer

Lakmal Warusawithana
OpenChoreo / WSO2

Extending original skills created by
Isala Piyarisi
