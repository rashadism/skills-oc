# OpenChoreo MCP — Platform Engineer view

PE-focused catalog for OpenChoreo's control-plane MCP server. Tools the developer skill rarely touches (ComponentType / Trait / Workflow CRUD, Environment / DeploymentPipeline writes, plane reads, ComponentRelease) are surfaced first.

| Server | Purpose |
|---|---|
| Control plane (`openchoreo-cp`) | Resource CRUD, schemas, workflows, releases, per-binding events and pod logs |

> For per-binding pod logs and events, use `get_resource_logs` / `get_resource_events` (control plane). For controller / plane / Argo / fluent-bit / OpenSearch logs, drop to `kubectl logs` against the appropriate plane namespace.

> Tool names below are bare (e.g. `create_environment`). The actual callable name carries an agent-specific prefix wrapping the server name — Claude Code uses `mcp__openchoreo-cp__<tool>`. Apply whatever prefix your coding agent expects.

## What MCP can NOT do for you (use kubectl)

| Capability | MCP status | Use instead |
|---|---|---|
| `SecretReference` create / update / delete | none | `kubectl apply -f` (`list_secret_references` for reads) |
| `AuthzRole` / `ClusterAuthzRole` and bindings — full CRUD | none | `kubectl apply -f` for writes; `kubectl get <kind> <name> -o yaml` for reads |
| `ObservabilityAlertsNotificationChannel` — full CRUD | none | `kubectl apply -f` for writes; `kubectl get observabilityalertsnotificationchannel <name> -o yaml` for reads |
| Plane resources (`DataPlane`, `WorkflowPlane`, `ObservabilityPlane` and cluster variants) — write | reads only | `kubectl apply -f` (Helm for the actual install) |
| Hard delete of `Component`, `Workload`, `ReleaseBinding`, `Project`, `Namespace` | none | `kubectl delete <kind> <name>` — confirm with user |
| `ClusterSecretStore` (External Secrets Operator) | not OpenChoreo | `kubectl` in DataPlane |
| `ClusterWorkflowTemplate` (Argo Workflows) | not OpenChoreo | `kubectl` in WorkflowPlane |
| `Gateway` / `HTTPRoute` / `GatewayClass` (Kubernetes Gateway API) | not OpenChoreo | `kubectl` in DataPlane |
| Helm install / upgrade for control plane / planes / cluster-agent | not in scope of MCP | `helm` |
| Controller / cluster-gateway / cluster-agent log inspection | observer plane only handles app logs | `kubectl logs` per cluster |
| Incident state changes (acknowledge, resolve, write RCA) | none | not available from this skill — ask the user to handle out of band |

These are not blockers — they're just two-step (`kubectl apply -f`) or out-of-band (Helm or out-of-scope UI work). When the user asks for one of them, do the work via the right path and call out the gap if relevant.

## PE write surface (full CRUD via MCP)

### Environments

| Tool | Purpose |
|---|---|
| `list_environments` | List environments in a namespace |
| `create_environment` | Create an Environment. Required: `namespace_name`, `name`, `data_plane_ref`. Optional: `display_name`, `description`, `data_plane_ref_kind` (`DataPlane` or `ClusterDataPlane`, default `DataPlane`), `is_production`. Takes scalar fields — the tool builds the CRD spec. |
| `update_environment` | Partial update of `display_name`, `description`, `is_production`. **`data_plane_ref` is immutable** — to re-point, delete and recreate. |
| `delete_environment` | Delete by `env_name`. Verify no ReleaseBindings depend on it first (`list_release_bindings` for each component). |

### DeploymentPipelines

| Tool | Purpose |
|---|---|
| `list_deployment_pipelines` / `get_deployment_pipeline` | Read |
| `create_deployment_pipeline` | Required: `namespace_name`, `name`. Optional: `display_name`, `description`, `promotion_paths[]`. Each path: `source_environment_ref` (string) + `target_environment_refs[]` (each `{name}`). Tool auto-sets `kind: Environment` on the source ref. |
| `update_deployment_pipeline` | Replaces `promotion_paths` wholesale when passed (full-replacement for that field). |
| `delete_deployment_pipeline` | By `pipeline_name`. |

### ComponentType / ClusterComponentType

| Tool | Purpose |
|---|---|
| `list_component_types` / `get_component_type` / `get_component_type_schema` (and cluster variants `list_cluster_component_types`, `get_cluster_component_type`, `get_cluster_component_type_schema`) | Read existing types |
| `get_component_type_creation_schema` / `get_cluster_component_type_creation_schema` | JSON schema for the `spec` body of `create_*` — fetch this before authoring |
| `create_component_type` / `create_cluster_component_type` | Required: `name` + full `spec` object matching the creation schema. Cluster variant has no `namespace_name`. Optional: `display_name`, `description`. |
| `update_component_type` / `update_cluster_component_type` | **Full-spec replacement.** `get_*` first, modify, send the whole spec back. |
| `delete_component_type` / `delete_cluster_component_type` | By name. |

### Trait / ClusterTrait

| Tool | Purpose |
|---|---|
| `list_traits` / `get_trait` / `get_trait_schema` (and cluster variants) | Read |
| `get_trait_creation_schema` | JSON schema for `create_trait` (covers both scopes) |
| `create_trait` / `create_cluster_trait` | Required: `name` + full `spec`. Cluster variant has no `namespace_name`. |
| `update_trait` / `update_cluster_trait` | **Full-spec replacement.** |
| `delete_trait` / `delete_cluster_trait` | By name. |

> **`ClusterTrait` does NOT support `spec.validations`.** Only namespace-scoped `Trait` does. The cluster variant rejects validations.

### Workflow / ClusterWorkflow

| Tool | Purpose |
|---|---|
| `list_workflows` / `get_workflow` / `get_workflow_schema` (and cluster variants) | Read |
| `create_workflow` / `create_cluster_workflow` | Required: `name` + full `spec` (including `runTemplate` — the inline Argo Workflow). No creation_schema tool exists; the spec shape is well-known (Argo + OpenAPIV3Schema for `parameters`). |
| `update_workflow` / `update_cluster_workflow` | **Full-spec replacement.** |
| `delete_workflow` / `delete_cluster_workflow` | By name. |

> The Workflow CR is one half of CI. The other half — `ClusterWorkflowTemplate` (Argo's reusable steps) — has no MCP path. Apply those with `kubectl` in the WorkflowPlane.

### Component releases

| Tool | Purpose |
|---|---|
| `list_component_releases` | List releases for a component |
| `get_component_release` | Spec snapshot for a specific release |
| `get_component_release_schema` | Schema for ComponentRelease |
| `create_component_release` | Generate a new release from current Component + Workload state. Auto-created when `auto_deploy: true` and Workload changes; manual create is rare. |

### Namespace, project (create-only — no delete)

| Tool | Purpose |
|---|---|
| `list_namespaces` / `create_namespace` | Required: `name`. Optional: `display_name`, `description` (stored as `openchoreo.dev/...` annotations). |
| `list_projects` / `create_project` | Required: `namespace_name`, `name`. Optional: `description`, `deployment_pipeline` (string — defaults to `"default"`). The CRD's `deploymentPipelineRef` object reference is built server-side. |

> **No `delete_namespace`, no `delete_project`** in MCP. Use `kubectl delete namespace <ns>` / `kubectl delete project <name>` against the control plane. Confirm with the user — destructive.

## PE read surface

### Plane resources (read-only via MCP)

| Tool | Purpose |
|---|---|
| `list_dataplanes` / `get_dataplane` (and `list_cluster_dataplanes` / `get_cluster_dataplane`) | DataPlane registration, gateway endpoint, secret-store ref, agent connection state |
| `list_workflowplanes` / `get_workflowplane` (and cluster variants) | WorkflowPlane registration, agent state |
| `list_observability_planes` / `get_observability_plane` (and cluster variants) | ObservabilityPlane registration, observer URL, agent state |

Writes — registering a new plane, updating gateway config — go through `kubectl apply -f` against the control plane CR, plus Helm to install the actual cluster-agent / data plane / workflow plane.

### Secret references (read-only via MCP)

| Tool | Purpose |
|---|---|
| `list_secret_references` | List secret references in a namespace |

Create / update / delete via `kubectl apply -f` (the OpenChoreo CRD) and the corresponding ESO `ClusterSecretStore` (kubectl in DataPlane).

### Components / Workloads / ReleaseBindings (read-side details)

PEs frequently look at developer-side resources to triage cross-skill issues. The same MCP tools the developer skill uses apply here:

- `list_components` / `get_component` / `get_component_schema`
- `list_workloads` / `get_workload` / `get_workload_schema`
- `list_release_bindings` / `get_release_binding` (status + endpoints)
- `list_workflow_runs` / `get_workflow_run`
- `get_workflow_run_logs` (live logs for a run; optional `task`, optional `since_seconds`; **live-only** — no archived logs for completed runs)
- `get_workflow_run_events` (K8s events for a run; optional `task`; useful for scheduling and pod-startup failures)
- `list_secret_references`

For **modifying** developer-side resources, prefer pairing with `openchoreo-developer` (the developer skill is MCP-only and owns those workflows).

## PE-side workflow patterns

### 1. Author or update a ClusterComponentType

```
get_cluster_component_type_creation_schema   → discover spec shape
create_cluster_component_type                 → name + spec body
get_cluster_component_type <name>              → verify
```

For an existing type:

```
get_cluster_component_type <name>              → fetch full spec
# modify locally
update_cluster_component_type                  → name + full modified spec
```

For incremental edits to a large CEL template, `kubectl apply -f` against an edited YAML is often easier than `update_*`'s full-replacement model. The two paths are equivalent — pick whichever leaves a cleaner diff.

### 2. Author or update a ClusterTrait

Same shape:

```
get_trait_creation_schema   (covers both Trait and ClusterTrait)
create_cluster_trait        → name + spec
update_cluster_trait        → full-spec replacement
delete_cluster_trait
```

> `ClusterTrait` has no `validations` field — the API rejects it. Use namespace-scoped `Trait` if validations are needed.

### 3. Author or update a Workflow / ClusterWorkflow

```
list_cluster_workflows                → see what exists
get_cluster_workflow_schema <name>    → existing parameter schema (if updating)
create_cluster_workflow               → name + spec (parameters + runTemplate + externalRefs + resources)
update_cluster_workflow               → full-spec replacement
```

Reusable Argo steps (`ClusterWorkflowTemplate`) live in the WorkflowPlane and are applied with `kubectl`. The OpenChoreo `Workflow.spec.runTemplate` references them via `templateRef`.

### 4. Set up a new Environment + promotion path

```
create_environment                     → name, data_plane_ref(_kind), is_production
list_environments                       → confirm
create_deployment_pipeline (or update) → add the new env to a promotion path
get_deployment_pipeline                 → verify
```

`update_deployment_pipeline` replaces `promotion_paths` wholesale when passed — read the current pipeline first if you're appending a path rather than rewriting all of them.

### 5. Diagnose a failing app deployment from the PE side

```
get_component                          → spec + status.conditions
get_release_binding                    → per-env state, endpoints, condition messages
get_resource_events                    → K8s events on Deployment / Pod (image pull, scheduling, OOM)
get_resource_logs                      → raw container logs for a specific pod under a binding
```

For longer-horizon log/metric/trace history, alerts, or incidents, use `kubectl logs` against the appropriate plane (fluent-bit / OpenSearch / observer in the observability plane for stored telemetry). Build logs have an MCP path — `get_workflow_run_logs` (live) and `get_workflow_run_events` for the same run. See `references/troubleshooting.md`.

For platform-side failures (controller stuck, gateway misconfigured, agent disconnected), drop to `kubectl logs` in the appropriate cluster — see `references/troubleshooting.md`.

### 6. Inspect plane health

```
list_dataplanes / get_dataplane             → status.agentConnection, gateway config, secretStoreRef
list_workflowplanes / get_workflowplane     → workflow plane connectivity
list_observability_planes / get_observability_plane → observer endpoint, agent state
```

If a plane shows `agentConnection: disconnected`, the cluster-agent in that remote cluster needs investigation — `kubectl logs` against the agent pod, check its mTLS cert vs. the control-plane CR's `clientCA` ref.

### 7. Roll a ComponentType change forward

```
get_cluster_component_type <name>      → current spec
# edit template / patches / parameters / validations locally
update_cluster_component_type          → send full spec back
list_components <ns>                    → see what already uses this type
get_component <name>                    → check status.conditions for re-validation results
```

Existing Components don't auto-roll. They re-render at next reconcile, which usually happens on the next ReleaseBinding update. Trigger it explicitly via `update_release_binding` or wait for the next dev-side change.

## Logs and telemetry beyond MCP

For per-binding pod logs and events, use `get_resource_logs` / `get_resource_events` (control plane). For longer-horizon log/metric/trace history, alerts, or incidents, use `kubectl logs` against the relevant plane:

- Build logs — `get_workflow_run_logs <run-name>` (live; pair with `get_workflow_run_events` for scheduling/pod-startup issues). For *completed* failed runs the live-log endpoint returns nothing; fall back to `kubectl logs --previous <argo-pod> -n openchoreo-workflow-plane -c <step>`.
- Application runtime logs (stored) — `kubectl logs deployment/observer -n openchoreo-observability-plane`, plus the OpenSearch / fluent-bit pods in that namespace if tracing the pipeline itself.
- Alerts / incidents — `kubectl get observabilityalertrule -A` for rule presence; incident state changes are out of scope for this skill.

See `references/troubleshooting.md` for the full pod-log map.

## Gotchas

**`update_*` for ComponentType / Trait / Workflow is full-spec replacement.** Always `get_*` first, modify locally, send the complete spec back. Omitting a field deletes it. For one-line CEL or template tweaks, `kubectl apply -f` against an edited YAML is often easier.

**`update_environment` is partial; `data_plane_ref` is immutable.** Re-pointing an Environment to a different DataPlane requires delete + recreate, which orphans existing ReleaseBindings.

**`create_release_binding` requires `release_name`.** All five of `namespace_name`, `project_name`, `component_name`, `environment`, `release_name` are required. Find prior release names via `list_component_releases`.

**`ClusterComponentType` may only reference `ClusterTrait` and `ClusterWorkflow`.** Cluster-scoped types cannot use namespace-scoped traits or workflows in `allowedTraits` / `allowedWorkflows`.

**`ClusterTrait` rejects `spec.validations`.** Use the namespace-scoped `Trait` if validations are needed.

**`get_resource_events` parameters are exact-match.** Required: `namespace_name`, `release_binding_name`, `group`, `version`, `kind`, `resource_name`. For core resources, `group: ""`. Use `get_release_binding` first to discover the kind/name of the workload's Deployment / Pod.

**`get_resource_logs` is direct kubectl-style logs.** It goes through the cluster gateway to the data plane, not through the observer store. Pod must currently exist; previous-container logs are not retrievable. For pods that are gone, fall back to `kubectl logs --previous` against the data-plane cluster directly.

**ObservabilityPlane (the CRD) must be installed and healthy** for the in-cluster observability stack to ingest data. If `kubectl logs` against `observer` / `fluent-bit` / `opensearch` shows pipeline failures, inspect plane registration via `get_observability_plane` and `kubectl get observabilityplane <name> -o yaml`.
