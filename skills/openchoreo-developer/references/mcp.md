# OpenChoreo MCP

Single source of truth for OpenChoreo's two MCP servers as used by `openchoreo-developer`: tool catalog, workflow patterns (create a component, build, deploy, debug, deploy a multi-service third-party app), and every gotcha.

| Server | Purpose |
|---|---|
| Control plane (`openchoreo-cp`) | Resource CRUD, schemas, workflows, releases |
| Observability (`openchoreo-obs`) | Logs, metrics, traces, spans, alerts, incidents |

Both must be configured separately; neither covers the other's surface.

> Tool names below are bare (e.g. `get_component`). The actual callable name carries an agent-specific prefix wrapping the server name — Claude Code uses `mcp__openchoreo-cp__<tool>` and `mcp__openchoreo-obs__<tool>`. Apply whatever prefix your coding agent expects.

> **This is the only tool surface for `openchoreo-developer`.** Real gaps where MCP has no write surface anywhere — escalate to `openchoreo-platform-engineer`:
> - **SecretReference** create / update / delete (no `create_secret_reference` tool exists in either toolset).
> - **Component `spec.traits[]` attachment** — `patch_component` only accepts `auto_deploy` and `parameters`; trait attachment requires editing the full Component spec.
> - **Hard delete** of any resource (Component, Workload, ReleaseBinding, Project, Namespace) — there are no `delete_*` tools for these. To take a deployment offline, use `update_release_binding_state release_state: Undeploy`.
>
> Note: Environment / DeploymentPipeline / ComponentType / Trait / Workflow / plane CRUD **does** have MCP tools, but they're PE territory. Activate `openchoreo-platform-engineer` rather than calling them from here.

## Control plane tool catalog

### Namespace, project, secrets

| MCP Tool | Purpose |
|---|---|
| `list_namespaces` | List all namespaces |
| `create_namespace` | Create a namespace |
| `list_projects` | List projects in a namespace |
| `create_project` | Create a new project (accepts `deployment_pipeline_ref` parameter) |
| `list_secret_references` | List secret references (read-only — create/update/delete have no MCP surface; route to `openchoreo-platform-engineer`) |

### Component

| MCP Tool | Purpose |
|---|---|
| `list_components` | List components in a project |
| `get_component` | Get component spec and status |
| `create_component` | Create a new component. Required: `namespace_name`, `project_name`, `name`, `component_type` (string in `{workloadType}/{name}` form). `auto_deploy` defaults to `true` if omitted. Optional `workflow` object turns it into a source-build component. For **BYO-image** components, follow with `create_workload`. For **source-build** components (with `workflow`), the workload is auto-generated as `{component}-workload`. |
| `patch_component` | Partial update — accepts only `auto_deploy` and `parameters`. **Does NOT cover `spec.traits[]` attachment or workflow changes** — those need PE. |
| `get_component_schema` | Get component spec schema |

### Workload

| MCP Tool | Purpose |
|---|---|
| `list_workloads` | List workloads for a component |
| `get_workload` | Get workload spec and status |
| `create_workload` | Create a workload for a **BYO-image** component. Takes `namespace_name`, `component_name`, `workload_spec` (no separate `name` parameter — name comes from `workload_spec.metadata.name` or auto-generates as `{component}-workload`). **Do NOT use for source-build components.** |
| `update_workload` | **Full-spec replacement**, not partial patch — read first via `get_workload`, modify locally, send the complete `workload_spec` back. Owner metadata is preserved server-side. Primary use: enrich the auto-generated workload of a source-build component when the repo has no `workload.yaml` descriptor. |
| `get_workload_schema` | Get the JSON schema for `workload_spec` |

### ReleaseBinding (deployment to an environment)

| MCP Tool | Purpose |
|---|---|
| `list_release_bindings` | List release bindings for a component |
| `get_release_binding` | Get a specific release binding (status, deployed endpoints, resolved dependencies) |
| `create_release_binding` | Deploy a component release to an environment. Required: `namespace_name`, `project_name`, `component_name`, `environment`, `release_name`. Optional: `component_type_environment_configs`, `trait_environment_configs`, `workload_overrides`. Fails if a binding already exists for that environment — use `update_release_binding` instead. |
| `update_release_binding` | **Partial update** — only fields you pass change. Use to deploy a different release (`release_name`) or update overrides on an existing binding. Environment is immutable. |
| `update_release_binding_state` | Set state: `Active` or `Undeploy`. Undeploy removes data-plane resources but keeps the binding record. |

> No `patch_release_binding` and no `delete_release_binding` tool exist. Use `update_release_binding` for changes; use `update_release_binding_state` with `Undeploy` to remove the data-plane resources.

### Build / workflow runs

| MCP Tool | Purpose |
|---|---|
| `trigger_workflow_run` | Trigger a build for a component using its configured workflow. Optional `commit` parameter pins the build to a specific SHA. |
| `create_workflow_run` | Queue a standalone workflow run by workflow name with explicit parameters (not tied to a component). |
| `list_workflow_runs` | List workflow run history (filter by namespace, optional project / component) |
| `get_workflow_run` | Get a specific workflow run (status, conditions, per-task phases) |

### Component types, traits, workflows (read paths a developer uses)

| MCP Tool | Purpose |
|---|---|
| `list_component_types` / `get_component_type` / `get_component_type_schema` | Namespace-scoped component types |
| `list_cluster_component_types` / `get_cluster_component_type` / `get_cluster_component_type_schema` | Cluster-scoped component types |
| `list_traits` / `get_trait` / `get_trait_schema` | Namespace-scoped traits |
| `list_cluster_traits` / `get_cluster_trait` / `get_cluster_trait_schema` | Cluster-scoped traits |
| `list_workflows` / `get_workflow` / `get_workflow_schema` | Namespace-scoped workflow templates |
| `list_cluster_workflows` / `get_cluster_workflow` / `get_cluster_workflow_schema` | Cluster-scoped workflow templates |

> The `_schema` variants return the JSON schema you pass into `parameters`. The plain `get_*` variants return the full resource (templates, allowed workflows, validation rules).

### Environments and deployment pipelines (read for developers)

| MCP Tool | Purpose |
|---|---|
| `list_environments` | List environments in a namespace |
| `list_deployment_pipelines` | List deployment pipelines |
| `get_deployment_pipeline` | Inspect promotion paths |

> Write tools exist (`create_environment`, `create_deployment_pipeline`, etc.) but are PE territory — activate `openchoreo-platform-engineer`.

### Component releases

| MCP Tool | Purpose |
|---|---|
| `list_component_releases` | List releases for a component (use this to find prior release names for rollback) |
| `get_component_release` | Get the immutable spec snapshot of a specific release |
| `get_component_release_schema` | Schema for ComponentRelease |
| `create_component_release` | Generate a new release from the current component state (auto-created when `auto_deploy: true` and Workload changes — manual create is rare) |

### Diagnostics (data-plane resources under a ReleaseBinding)

| MCP Tool | Purpose |
|---|---|
| `get_resource_events` | Kubernetes events for a Deployment / Pod / Service / etc. under a binding (use for `ImagePullBackOff`, scheduling failures, OOM kills — events the pod logs can't show) |
| `get_resource_logs` | Raw container logs for a specific pod under a binding (use for crashloops where `query_component_logs` returns empty because the container never started) |

## Observability tool catalog

| MCP Tool | Purpose |
|---|---|
| `query_component_logs` | Runtime logs for a component in a given environment |
| `query_workflow_logs` | Build / workflow run logs |
| `query_http_metrics` | HTTP request rate, latency, and error metrics |
| `query_resource_metrics` | CPU and memory usage for a component |
| `query_traces` | Search distributed traces for a component |
| `query_trace_spans` | List spans within a trace |
| `get_span_details` | Full detail for a single span |
| `query_alerts` | Query fired alert events for a component / environment |
| `query_incidents` | Query incidents created from alerts; includes update endpoint for triage |

## Exploration Workflow

When connecting to an unfamiliar cluster, explore in this order:

```
1. list_namespaces
2. list_projects(namespace)
3. list_environments(namespace)
4. list_deployment_pipelines(namespace)
5. list_cluster_component_types       → cluster-wide types (most common)
6. list_component_types(namespace)    → namespace-scoped types (if any)
7. list_cluster_traits                → cluster-wide traits
8. list_cluster_workflows             → cluster-scoped build workflows
9. list_workflows(namespace)          → namespace-scoped workflows (if any)
10. list_components(namespace, project) → components already deployed
```

## Workflow Patterns

### 1. Scaffold and Create a Component

Discover what's available before authoring YAML:

```
list_cluster_component_types       → find available workload types (e.g. deployment/service)
get_cluster_component_type_schema  → inspect fields and options for a type
list_cluster_traits                → find available traits (e.g. ingress, storage)
get_cluster_trait_schema           → inspect trait fields
get_component_schema               → get the full Component resource schema
```

Then create:

```
create_component(namespace, project, name, spec_yaml)
```

For BYO image deployments, **omit `workflow` from the component spec**.

### 2. Build (Trigger Workflow)

```
list_workflows(namespace)                               → what workflows are available?
list_workflow_runs(namespace, project, component)       → check existing run history
trigger_workflow_run(namespace, project, component)     → kick off a build
get_workflow_run(namespace, project, component, run_id) → check run status
```

### 3. Activate and Manage Deployments

After a build completes, release bindings are created automatically (or on first `create_workload` for BYO):

```
list_release_bindings(namespace, project, component)              → see binding per environment
get_release_binding(namespace, binding_name)                      → inspect status, endpoints, state
update_release_binding_state(namespace, binding_name, Active)     → activate a deployment
update_release_binding_state(namespace, binding_name, Undeploy)   → undeploy from an environment
update_release_binding(namespace, binding_name, release_name=…,
                       component_type_environment_configs=…,
                       trait_environment_configs=…,
                       workload_overrides=…)                       → update release pointer / overrides (partial)
```

> Deployment is via `create_release_binding` (added in v1.0.0-rc.2). There is no separate `deploy_release` or `promote_component` tool. To promote to a downstream environment, create a new ReleaseBinding for that environment via `create_release_binding`, then call `update_release_binding_state` with `Active`.

### 4. Inspect and Debug

```
get_component(namespace, project, component)         → spec + status conditions
list_workloads(namespace, project, component)        → running workloads
get_workload(namespace, workload_name)               → workload details
list_release_bindings(namespace, project, component) → binding per environment
get_release_binding(namespace, binding_name)         → binding status, endpoints, invokeURL
list_secret_references(namespace)                    → available secrets
```

### 5. Query Logs and Metrics (observability MCP)

`query_component_logs` is the fastest way to triage runtime behavior from the AI assistant. `query_workflow_logs` covers build/CI logs.

```
query_component_logs(namespace, project, component, environment)   → runtime logs
query_workflow_logs(namespace, project, component, workflow_run)   → build logs
query_http_metrics(namespace, project, component, environment)     → request rate / latency / errors
query_resource_metrics(namespace, project, component, environment) → CPU and memory
```

Trace debugging:

```
query_traces(namespace, project, component, environment) → find relevant traces
query_trace_spans(trace_id)                              → list spans in a trace
get_span_details(span_id)                                → inspect a single span
```

### 6. Create or Update a Workload

The right tool depends on whether the component uses a build workflow:

**BYO-image component** (no `spec.workflow`) — developer creates the workload:
```
get_workload_schema(namespace, project, component)         → understand workload fields first
create_workload(namespace, project, component, name, spec) → create workload
list_workloads(namespace, project, component)              → verify it appears
```

**Source-build component** (`spec.workflow` set) — workload is auto-generated by the build (named `{component}-workload`):
```
trigger_workflow_run(namespace, project, component)        → kick off the build
list_workloads(namespace, project, component)              → confirm {component}-workload appears after the build
get_workload(namespace, '{component}-workload')            → inspect what the build produced
update_workload(namespace, '{component}-workload', spec)   → enrich (endpoints, deps, env, files) ONLY if repo has no workload.yaml
```

**Preferred path for enriching source-build workloads**: edit `workload.yaml` in the source repo and rebuild. The build re-creates the workload with the descriptor inlined. Reach for `update_workload` only when you can't or don't want to rebuild.

> `update_workload` takes only `namespace_name`, `workload_name`, `workload_spec` — not `project_name` or `component_name`. Use `list_workloads` to find the workload name first.

> The auto-generated workload is **always** named `{component}-workload`, even if `workload.yaml` declares a different `metadata.name` — the build overrides it. So `get_workload workload_name: my-svc` returns "not found"; use `workload_name: my-svc-workload`.

### 7. Deploy a Third-Party / Multi-Service App with Pre-built Images

When the user asks to deploy a well-known public or open-source multi-service app:

```
# 1. Find pre-built images — check release/ directory, README, CI pipelines
WebFetch or gh to fetch official kubernetes-manifests.yaml (or Helm values, docker-compose)
   → extract image URLs and ALL env vars per service

# 2. Create project
create_project(namespace, name)

# 3. Create all components — NO workflow parameter
create_component(namespace, project, name, componentType)   → repeat for each service
   componentType examples:
     deployment/service         → backend gRPC/REST/TCP services
     deployment/web-application → public-facing frontend
     deployment/worker          → background workers, load generators
     statefulset/datastore      → stateful stores (Redis, databases)

# 4. Create workloads, dependency-free first
# Pass 1: services with no dependencies (simpler, fewer failure modes)
# Pass 2: services that depend on Pass 1 services
create_workload(namespace, project, component, name, spec)  → repeat for each service

# 5. Verify each component
list_release_bindings(namespace, component)  → Ready or ResourcesProgressing?

# 6. Investigate any failing component immediately — don't assume platform issue
query_component_logs(namespace, project, component, environment)
   → crash before "listening on port"? → vendor SDK crash, missing env var, or startup panic
   → connection refused from another service? → dependency not yet ready or wrong port/env var
```

**Key rules for this workflow:**

- Never set `workflow` in `create_component` for BYO image deployments.
- Always extract ALL env vars from official manifests — dependencies inject service addresses but not `PORT`, feature flags, or vendor SDK disable flags.
- If a service crash-loops before logging a "listening" message, look for a native module load error or vendor SDK init failure — apply the disable flag from the official manifests.
- If a required env var references an optional or not-yet-deployed service, set a placeholder value to prevent startup panics.
- `dependencies` is an **object containing an `endpoints` array** — entries live under `dependencies.endpoints[]`, with `name` for the target endpoint (not `endpoint`).
- Source builds fail for repos that use `ARG BUILDPLATFORM` multi-stage syntax (exit code 125) — switch to BYO immediately when you see this error.

## Gotchas

**Component type format is `workloadType/typeName`**: Use `get_cluster_component_type_schema` to see accepted values before setting `spec.componentType.name`.

**`get_component` and `get_workload` include status.conditions**: Each condition has `type`, `status`, `reason`, `message`. Always check conditions when debugging.

**`list_release_bindings` requires both project and component**: You must pass both, not just project.

**`get_workload_schema` before writing workload YAML**: Call this to discover the field shape rather than guessing. `dependencies` is an object with an `endpoints` array — see the gotcha below.

**`dependencies` is nested**: The Workload `dependencies` field is an **object** containing an `endpoints` array, not a flat array. Each entry uses `name` (target endpoint name), not `endpoint`:
```yaml
dependencies:
  endpoints:
    - component: backend-api
      name: api                # the target endpoint name on backend-api
      visibility: project       # project | namespace
      envBindings:
        address: BACKEND_URL
```
Field renamed from `connections` in v1.0.0.

**`trigger_workflow_run` vs `create_workflow_run`**: `trigger_workflow_run` starts a build for a component using its configured workflow (pass optional `commit` SHA to pin to a revision). `create_workflow_run` creates a standalone run by workflow name with explicit parameters — use for workflows not tied to a component.

**Workflow runs can lag**: A just-triggered workflow may briefly show no runs. Call `list_workflow_runs` after a moment, then verify with `get_component`.

**Two separate MCP servers**: `openchoreo-cp` (control plane) and `openchoreo-obs` (observability) — both must be configured.

**`update_workload` only takes `namespace_name`, `workload_name`, `workload_spec`**: It does not accept `project_name` or `component_name`. Use `list_workloads` to find the workload name first.

**Observability data requires a live ObservabilityPlane**: If queries return no data, the plane may be missing or unhealthy. Escalate to `openchoreo-platform-engineer`.

**TCP `address` binding injects `host:port`, not a protocol DSN**: For databases (PostgreSQL, MySQL) and message brokers (NATS, Redis), the injected `address` value is a plain `host:port` string. Apps that expect `postgres://user:pass@host/db` or `nats://host:4222` will fail to parse it. Declare the dependency for the topology diagram but set the full DSN as a literal env var instead. Get the hostname from `get_release_binding` → `endpoints[*].serviceURL.host`.

**Source-build workloads have no endpoints or dependencies until you add them**: The `generate-workload-cr` build step creates a minimal workload with just the image. If the repo has no `workload.yaml`, always call `update_workload` after a successful build to add endpoints, env vars, and dependencies. Without this the component deploys but has no routing, no dependencies, and the cell diagram renders incomplete.

**File mount `mountPath` is a directory**: The controller appends the `key` name to `mountPath` to form the final file path. Set `mountPath` to the parent directory (`/usr/share/nginx/html`), not the full file path (`/usr/share/nginx/html/config.json`). Using the full file path doubles the filename: `.../config.json/config.json`.

**Browser-facing apps need `https://` and `wss://` backend URLs**: OpenChoreo serves web-application components over HTTPS. Any backend URLs injected at runtime (e.g., via a mounted `config.json`) must use `https://` and `wss://`. HTTP/WS URLs are blocked by browsers as mixed content — no visible error, requests just silently fail. Always get external URLs from `get_release_binding` → `endpoints[*].externalURLs` and use the `https` scheme.
