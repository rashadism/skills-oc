---
name: openchoreo-core
description: Core OpenChoreo reference — resource concepts, `occ` CLI install and usage, MCP tool catalog, and resource YAML schemas. Use to look up "what is X in OpenChoreo", how to install or log in to `occ`, which MCP tool covers Y, or the shape of a resource YAML. Prerequisite for `openchoreo-developer`, `openchoreo-install`, and `openchoreo-platform-engineer`.
metadata:
  version: "1.0.0"
---

# OpenChoreo Core

Shared foundation for the OpenChoreo skill family. Holds the universal material — concepts, CLI setup, MCP tool catalog, resource schemas — so the workflow-specific skills stay focused on their domain.

When `openchoreo-developer`, `openchoreo-install`, or `openchoreo-platform-engineer` says **PREREQUISITE: `openchoreo-core/SKILL.md`**, this is what they mean.

## Reference routing

- `references/concepts.md` — resource hierarchy (Namespace → Project → Component → Workload → Release → ReleaseBinding), Cell architecture, endpoint visibility, planes, API version.
- `references/cli.md` — `occ` install, login, context setup, command surface, global flags, exploration workflow, universal gotchas.
- `references/mcp.md` — control-plane and observability MCP tool catalog, universal exploration workflow, MCP-specific gotchas.
- `references/resource-schemas.md` — full YAML for Project, Component, Workload, Workload Descriptor, Environment, DeploymentPipeline, ReleaseBinding, SecretReference, plus read-only ComponentType / Trait shapes.

For workflow-specific commands and gotchas (deploying apps, installing planes, authoring ComponentTypes), go to the matching workflow skill once you have the foundation.

## Tool preference order

Across every OpenChoreo workflow:

1. **MCP tools first** (`mcp__openchoreo-cp__*` for control plane, `mcp__openchoreo-obs__*` for observability) — discoverable schemas, no shell quoting issues, correct typing.
2. **`occ` CLI** when a workflow isn't covered by MCP, or when scripting / running locally.
3. **`kubectl`** only when MCP and `occ` cannot reach the resource. Reach for it deliberately, not by default.

## Universal guardrails

- **`occ <resource> get <name>` returns full YAML** (spec + status). No `-o` flag. Primary inspection and debugging tool.
- **API version is `openchoreo.dev/v1alpha1`** for every OpenChoreo resource.
- **`deploymentPipelineRef` is an object**, not a string: `{kind: DeploymentPipeline, name: <name>}` (changed in v1.0.0).
- **`occ login --client-credentials` does not work with `service_mcp_client`** (the MCP-token service account) — `unauthorized_client` error. Use browser-based `occ login`.
- **Two separate MCP servers** — both must be configured; neither covers the other's surface.
- **`status.conditions` is the source of truth.** Always check before guessing.

## Pinned version

This skill set targets **OpenChoreo v1.0.0**. Field names, schemas, and CLI behavior may differ on other versions — verify against the live cluster before relying on a remembered shape.
