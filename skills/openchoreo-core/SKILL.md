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
- `references/cli.md` — `occ` install, login, context setup, full command surface, global flags, component lifecycle commands, exploration workflow, all CLI gotchas.
- `references/mcp.md` — control-plane and observability MCP tool catalog, workflow patterns (scaffold, build, deploy, debug, third-party-app deployment), all MCP gotchas.
- `references/resource-schemas.md` — full YAML for Project, Component, Workload, Workload Descriptor, Environment, DeploymentPipeline, ReleaseBinding, SecretReference, plus read-only ComponentType / Trait shapes.

> **Read the reference before you act.** Before running an `occ` command, consult `references/cli.md` for the exact subcommand shape and gotchas. Before calling an MCP tool, consult `references/mcp.md` for the tool's exact name and the workflow it sits in. Many natural-sounding commands (e.g. `occ context current`) do not exist — the references list the real ones, plus the non-obvious gotchas (flag-scope quirks, nested-field shapes, deleted endpoints, etc.). Don't guess.

For workflow-specific commands and gotchas (deploying apps, installing planes, authoring ComponentTypes), go to the matching workflow skill once you have the foundation.

## Tool preference order

```
1. MCP tools  (preferred — structured, schema-aware, no shell quoting)
2. occ CLI    (fallback when MCP doesn't expose the op, AND the natural choice
               for inherently CLI-only operations — see table below)
3. kubectl    (last resort — only when MCP and occ cannot reach the resource)
```

### When to use each

| Interface | When to use | Examples |
|---|---|---|
| **MCP** (`mcp__openchoreo-cp__*`, `mcp__openchoreo-obs__*`) | Default for resource CRUD, schema discovery, and **all** observability queries. Structured I/O, no shell quoting. | `list_projects`, `list_environments`, `get_component`, `create_component`, `patch_release_binding`, `create_release_binding`, `query_component_logs`, `query_workflow_logs`, `query_http_metrics`, `get_workload_schema` |
| **`occ` CLI** | When MCP doesn't expose the op, OR for inherently CLI-only operations. | `occ login`, `occ version`, `occ config context add/list/use`, `occ component scaffold`, `occ apply -f file.yaml`, `occ component logs` (CLI tail), `occ component workflow run/logs` |
| **`kubectl`** | Neither MCP nor `occ` covers the operation — controller logs, plane-level CRDs without MCP coverage, Helm. | `kubectl logs`, `kubectl describe`, `helm upgrade` |

### When `occ` is the right answer (not a fallback)

These operations have no MCP equivalent — go straight to `occ`:

- Auth: `occ login`, `occ login --client-credentials` (with the `service_mcp_client` caveat in guardrails)
- CLI state: `occ version`, `occ config controlplane`, `occ config credentials`, `occ config context add/list/use/update/delete`
- YAML authoring: `occ apply -f <file>` (any time you have a complete CR file on disk — almost always preferable to building a `create_*` MCP call by hand for non-trivial specs)
- Component scaffolding: `occ component scaffold` (no MCP equivalent for emitting templated YAML)

For everything else with an MCP tool listed in `references/mcp.md`, prefer MCP.

### User preference override

If the user states a preference, honor it for the session:
- **"Use occ" / "Use CLI"** → use `occ` for everything it supports; only fall back to MCP for operations that have no `occ` equivalent (e.g. some observability queries).
- **"Use MCP"** / no preference → MCP-first per the table above.
- **"Use kubectl"** → use `kubectl` only for K8s-level operations; OpenChoreo CRD operations still go through MCP/`occ`.

Even with an override, fall back through the chain for unsupported operations.

## Universal guardrails

- **`occ <resource> get <name>` returns full YAML** (spec + status). No `-o` flag. Primary inspection and debugging tool.
- **API version is `openchoreo.dev/v1alpha1`** for every OpenChoreo resource.
- **`deploymentPipelineRef` is an object**, not a string. `kind` is optional and defaults to `DeploymentPipeline`, so `{name: <name>}` is the typical form (changed in v1.0.0). Same shape applies to `sourceEnvironmentRef` / `targetEnvironmentRefs[]` in `DeploymentPipeline` — both are objects with `name` (and optional `kind`).
- **`occ login --client-credentials` does not work with `service_mcp_client`** (the MCP-token service account) — `unauthorized_client` error. Use browser-based `occ login`.
- **There is no `occ context` command.** Context management lives under `occ config context`. To inspect the active context, run `occ config context list` (the active one is marked `*`). Subcommands: `add | list | use | update | delete` — no `current`, `show`, or `get`.
- **`occ apply -f -` (stdin) does not work** — error `path - does not exist`. Always write YAML to a temp file first, then `occ apply -f /tmp/file.yaml`.
- **Workload `dependencies` is nested**: `dependencies.endpoints[]`, not flat `dependencies[]`. Each entry uses `name` for the target endpoint, not `endpoint`.
- **Two separate MCP servers** — both must be configured; neither covers the other's surface.
- **`status.conditions` is the source of truth.** Always check before guessing.

## Pinned version

This skill set targets **OpenChoreo v1.0.0**. Field names, schemas, and CLI behavior may differ on other versions — verify against the live cluster before relying on a remembered shape.
