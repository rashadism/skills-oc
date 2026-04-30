---
name: openchoreo-platform-engineer
description: |
  Use for OpenChoreo platform-level work: authoring ComponentTypes / Traits / Workflows, registering Environments / DeploymentPipelines / planes, configuring secret stores, identity, authz roles, gateways, observability alert channels, Helm install / upgrade, and troubleshooting platform-side failures. The audience is the platform engineer or operator running the OpenChoreo control plane and remote planes — not the application developer deploying onto it.
metadata:
  version: "1.0.0"
---

# OpenChoreo Platform Engineer Guide

Help with OpenChoreo platform-level work. Keep this file lean, discover the live platform shape via MCP, and read detailed references only when the task actually needs them.

## When to use this skill (and when not to)

Use this skill when the task touches the **platform** — the OpenChoreo control plane and the remote planes that run developer workloads:

- Authoring extensions — `ComponentType` / `ClusterComponentType`, `Trait` / `ClusterTrait`, `Workflow` / `ClusterWorkflow` (schema, templates, patches, CEL).
- Environments and pipelines — `Environment`, `DeploymentPipeline`, project-level configuration beyond ordinary developer use.
- Platform topology and lifecycle — cluster setup, plane registration (`DataPlane`, `WorkflowPlane`, `ObservabilityPlane`), multi-cluster connectivity, namespace management, deployment topology, Helm install / upgrade, upgrade ordering between planes.
- Integrations and security — secret stores (External Secrets Operator + ClusterSecretStore), container registries, identity providers (Thunder / external IdP), authorization roles and bindings, external CA / TLS, cluster-agent RBAC.
- API gateway — Kubernetes Gateway API in the DataPlane, gateway topology, Choreo modules.
- CI/CD governance — `Workflow` / `ClusterWorkflow` authoring, `ClusterWorkflowTemplate` (Argo) authoring, auto-build webhook config, `allowedWorkflows` gating on ComponentTypes.
- Observability platform-side — alert rule traits, `ObservabilityAlertsNotificationChannel`, logging / metrics / tracing adapter modules.
- Troubleshooting platform failures — failure isolation across planes, controller / gateway / cluster-agent logs.

**Don't use this skill — use the right one instead — when:**

- The task is about **deploying or debugging an application**: writing `Component` / `Workload` / `ReleaseBinding`, editing `workload.yaml`, tracing a runtime crash. → **`openchoreo-developer`** owns this.
- The task is about a **GitOps workflow** — repository layout, Flux CD, bulk promotion across environments via Git, the `occ` file-system mode (`componentrelease generate`, `releasebinding generate`). → A dedicated **GitOps skill** owns this; do not pull those flows into this skill.
- The task is **installing OpenChoreo from scratch** — initial Helm install, Colima / GCP / multi-cluster setup walkthrough. → **`openchoreo-install`** owns this. Once OpenChoreo is running, day-2 platform work comes back here.

**Pair this skill with `openchoreo-developer` when** the task crosses the platform / app boundary — for example, debugging "this app fails to deploy" where the root cause turns out to be a missing `ClusterTrait` or a misconfigured `DeploymentPipeline`. If both skills are available and the task touches both, use both immediately. Don't wait to fail on one side before loading the other.

## Tool surface

This skill uses two tool surfaces. **MCP first. `kubectl` only when MCP cannot reach the operation.**

| Surface | Used for |
|---|---|
| **MCP** (`openchoreo-cp` and `openchoreo-obs` servers) | Discovery / read of every OpenChoreo CRD; full CRUD for Environment, DeploymentPipeline, ComponentType (+cluster), Trait (+cluster), Workflow (+cluster), Project, Namespace, ComponentRelease; runtime diagnostics (events, pod logs, observability queries) |
| **`kubectl`** / **Helm** | Anything MCP can't do — see *MCP limitations* below — plus cluster-native concerns (Helm install / upgrade for control plane / planes / cluster-agent; `ClusterSecretStore` (External Secrets Operator); `ClusterWorkflowTemplate` (Argo); `Gateway` / `HTTPRoute` / `GatewayClass` (Kubernetes Gateway API)); raw `kubectl logs` for controllers / cluster-gateway / cluster-agent |

> **Tool naming.** Throughout this skill, MCP tools are referenced by their bare name (e.g. `create_environment`, `get_resource_logs`). The actual callable name carries an agent-specific prefix wrapping the server name — Claude Code uses `mcp__openchoreo-cp__<tool>` for control plane and `mcp__openchoreo-obs__<tool>` for observability. Other coding agents use different prefixes. Apply whatever your agent expects.

## MCP limitations — what MCP can NOT do today

These are the only places this skill drops out of MCP. None are blockers — `kubectl apply -f` against the relevant CRD does the job — but it's a two-step path and worth flagging when explaining to the user. The list also drives the MCP-server roadmap; see `notes.md` for the consolidated input.

### OpenChoreo CRDs without MCP write tools

For each of these, **author the YAML and apply with `kubectl apply -f <file>`** (or `kubectl apply -f -` from stdin / a heredoc). Reads where they exist still go through MCP.

1. **`SecretReference`** — `list_secret_references` exists; create / update / delete do not.
2. **`AuthzRole`, `ClusterAuthzRole`, `AuthzRoleBinding`, `ClusterAuthzRoleBinding`** — no MCP tools, neither read nor write. Inspect with `kubectl get authzrole <name> -o yaml`.
3. **`ObservabilityAlertsNotificationChannel`** — no MCP tools, neither read nor write. Inspect with `kubectl get observabilityalertsnotificationchannel <name> -o yaml`.
4. **Plane resources** — `DataPlane`, `WorkflowPlane`, `ObservabilityPlane`, and their cluster-scoped variants. Read tools exist (`list_dataplanes`, `get_dataplane`, etc.); create / update / delete do not. Helm handles the underlying plane install; the OpenChoreo CR is `kubectl apply -f`'d to register it.

### Hard delete of OpenChoreo resources

5. **`Component`, `Workload`, `ReleaseBinding`, `Project`, `Namespace`** — no `delete_*` MCP tools for these. Soft-undeploy a binding via `update_release_binding_state release_state: Undeploy`. For hard delete, `kubectl delete <kind> <name>` against the control plane. Always confirm with the user — it's destructive and orphans dependent resources.

### Operations outside MCP scope (no API path at all)

These cannot be completed from this skill. **Tell the user plainly and direct them to the right system.**

6. **Acknowledge / resolve incidents, write RCA reports** — Backstage portal only. (Read-only inspection via `query_incidents` is fine.)
7. **External IdP, Thunder bootstrap, Backstage SSO config** — IdP admin console + Helm values during install.
8. **External secret backend admin** — Vault / AWS Secrets Manager / OpenBao admin tooling. From this skill we only reach the Kubernetes-side `ClusterSecretStore` config and the OpenChoreo `SecretReference`.
9. **External Git provider config** — webhooks, deploy keys, repo permissions on GitHub / GitLab / Bitbucket. The skill can configure the OpenChoreo side of `autoBuild`; the Git provider side is in the provider's UI / API.
10. **Commercial WSO2 Choreo cloud resources** — different product (`~/.choreo/bin/choreo`). This skill manages OpenChoreo only.

When the user asks for an operation in 6–10, respond with: "This skill can't do X — it's not an OpenChoreo control-plane operation. You'll need to do it via [system]." Then explain the relevant pieces this skill *can* set up.

## Working style

Prefer progressive discovery over memorized specifics:

1. Identify the exact plane, namespace, resource, or failure domain.
2. Discover live state via MCP first — `get_component`, `get_release_binding`, `get_cluster_component_type_schema`, `list_environments`, etc. Drop to `kubectl` only when MCP can't reach what you need.
3. Read only the reference file that matches the task.
4. Make the smallest change that can prove or fix the issue.
5. Verify the result from the live cluster before moving on.

Treat the live cluster output and current repo as the source of truth. If a remembered field name, example, or behavior conflicts with current output, trust the current output and confirm in the relevant reference file or repository source.

Avoid loading all references up front. Pull them in only when the task requires that area.

## Reference routing

Foundational material:

- `references/concepts.md` — resource hierarchy, Cell architecture, endpoint visibility, planes, API version
- `references/mcp.md` — MCP tool catalog grouped by PE workflow, gaps, gotchas
- `references/resource-schemas.md` — universal YAML shapes for Project, Component, Workload, Environment, DeploymentPipeline, ReleaseBinding, SecretReference

PE-specific material:

**Authoring:**
- `references/component-types-and-traits.md` — ComponentType, ClusterComponentType, Trait, ClusterTrait authoring (schema, templates, patches, validation rules) — MCP-first; `kubectl apply -f` fallback for big spec edits
- `references/workflows.md` — Workflow / ClusterWorkflow authoring (schema, runTemplate, ClusterWorkflowTemplates, externalRefs, CI governance via `allowedWorkflows`) — MCP-first for Workflow / ClusterWorkflow; kubectl-only for ClusterWorkflowTemplate (Argo native)
- `references/cel.md` — CEL syntax, context variables, OpenChoreo built-in and helper functions used by all of the above
- `references/authz.md` — `AuthzRole` / `ClusterAuthzRole` / `AuthzRoleBinding` / `ClusterAuthzRoleBinding` authoring, action catalogue, request evaluation — `kubectl apply -f` only (MCP gap)

**Tooling:**
- `references/troubleshooting.md` — failure isolation, health checks, log locations, common failure patterns

For PE topics not bundled in these references — TLS / external CA, container registries, identity provider configuration, multi-cluster connectivity, deployment topology, observability adapter modules, API gateway modules, alert storage backend choice, IdP / bootstrap auth mappings, Backstage configuration, Helm upgrades — consult the official PE guide at **https://openchoreo.dev/docs/platform-engineer-guide/**. The docs are the source of truth for those topics; do not rely on memory.

## Discovery-first workflow

### 1. Classify the task

Decide whether the work is:

- Pure platform work (this skill alone)
- App work that needs PE help (paired with `openchoreo-developer`)
- A mixed task that needs both OpenChoreo skills

For mixed tasks, keep the app-facing thread and the platform-facing thread connected. Many deployment failures are caused by an interaction between Component config and platform config.

### 2. Inspect current state via MCP first

Start with the smallest useful inspection:

- `get_component` / `get_workload` / `get_release_binding` for app-facing resources (status conditions, endpoints).
- `get_cluster_component_type` / `get_cluster_trait` / `get_cluster_workflow` for platform extensions.
- `list_environments`, `list_deployment_pipelines`, plane reads for topology.
- `query_component_logs` / `query_workflow_logs` / `query_alerts` for runtime behaviour.
- `get_resource_events` / `get_resource_logs` for pod-level debugging through a binding.

Drop to `kubectl logs` only when MCP can't reach what you need — controller pods, cluster-gateway, cluster-agent.

### 3. Route to the right source of detail

After the first inspection, load the matching reference file. If the reference still leaves ambiguity, inspect the repository or generated CRDs, or check the live object shape on the cluster.

Keep the investigation targeted. Avoid a full-cluster inventory unless the failure is clearly systemic or the affected resource is still unknown.

### 4. Change one layer at a time

Platform tasks often span multiple layers:

- Helm install values
- Control plane CRDs (Environment, DeploymentPipeline, ComponentType, etc.)
- Remote plane resources (data plane Gateway, ESO ClusterSecretStore, Argo ClusterWorkflowTemplate)
- App-visible outcomes (available types, workflows, route reachability)

Change the layer that is actually responsible, then re-check the dependent layers. Don't "fix" an application symptom by guessing at platform internals.

### 5. Verify with live evidence

Verification should come from the platform, not assumption:

- Resource conditions changed as expected (`get_*` → `status.conditions[]`).
- Controller / agent logs show the new state.
- Helm release and pod rollout are healthy.
- The downstream app-facing symptom is gone.

If the platform change succeeded but the app still fails, hand off to or continue with `openchoreo-developer`.

## Stable guardrails

- **Default to the `default` namespace.** Unless the user explicitly asks to create a new namespace, provision environments, pipelines, and projects inside `default`. Always ask before creating a new namespace — new namespaces are a significant organisational boundary and should be a conscious decision.
- **MCP-first.** Use MCP for discovery and for any resource with an MCP write surface (Environment, DeploymentPipeline, ComponentType / cluster, Trait / cluster, Workflow / cluster, Project, Namespace, ComponentRelease, runtime diagnostics).
- **`kubectl apply -f` for OpenChoreo CRDs without an MCP write surface.** See *MCP limitations* above — `SecretReference`, authz CRDs, `ObservabilityAlertsNotificationChannel`, plane resources. These are not blockers; they're just two-step.
- **`update_component_type`, `update_trait`, `update_workflow` (and cluster variants) are full-spec replacement.** Read the current spec via `get_*` first, modify locally, send the complete spec back. Omitting a field deletes it. For one-line CEL or template tweaks, `kubectl apply -f` against an edited YAML is often easier.
- **`update_environment` is partial, but `data_plane_ref` is immutable.** Re-pointing an environment to a different plane requires delete + recreate (and re-binding any existing ReleaseBindings).
- **No MCP delete for Component, Workload, ReleaseBinding, Project, Namespace.** Use `update_release_binding_state release_state: Undeploy` for soft binding teardown. Hard delete needs `kubectl delete <kind> <name>` against the control plane — confirm with the user; it's destructive.
- **Plane resources are read-only via MCP.** Create / update / delete go through `kubectl apply -f` (and Helm for the actual cluster-agent / control-plane / data-plane install). Upgrade order matters; do not move a remote plane ahead of the control plane.
- **Scope matters.** Cluster-scoped and namespace-scoped resources are not interchangeable. `ClusterComponentType` may only reference `ClusterTrait` and `ClusterWorkflow`, not their namespace-scoped counterparts. `ClusterTrait` does **not** support the `validations` field (only namespace-scoped `Trait` does).
- **`status.conditions`, live resource YAML, and current controller logs are better truth sources than memory.** When a task needs exact controller behavior or CRD fields, inspect the repo or current docs instead of guessing.
- **Prefer reversible, inspectable changes** over broad edits across many planes or namespaces.

## Anti-patterns

- Loading every reference file before identifying the actual problem.
- Repeating stale examples without checking the current cluster or resource schema.
- Performing wide cluster sweeps before checking the affected object and logs.
- Treating app-level deployment symptoms as purely platform issues without checking the app resource chain.
- Making several platform changes at once and losing the causal signal.
- Creating a new namespace without asking the user — default to `default` unless explicitly told otherwise.
- Reaching for `kubectl` when an MCP tool exists for the operation. Reach for kubectl only for the gaps in *MCP limitations* above.
- Sending a partial `update_component_type` / `update_trait` / `update_workflow` spec — the call replaces the whole spec; missing fields are deleted.
- Telling the user to "use the MCP tool for X" when X is a gap in *MCP limitations*. Use `kubectl apply -f` directly and call out the limitation if asked.
- Reaching for `occ` — this skill does not use the `occ` CLI. GitOps-style file-mode flows belong in the dedicated GitOps skill.
