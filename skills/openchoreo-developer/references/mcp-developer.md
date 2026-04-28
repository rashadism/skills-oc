# OpenChoreo MCP — Developer Reference

Developer workflows mapped to MCP tools. For the universal tool catalog, observability tools, and shared gotchas, see `openchoreo-core/references/mcp.md`.

## Developer Workflows

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
list_release_bindings(namespace, project, component)           → see binding per environment
get_release_binding(namespace, binding_name)                   → inspect status, endpoints, state
update_release_binding_state(namespace, binding_name, Active)  → activate a deployment
update_release_binding_state(namespace, binding_name, Undeploy)→ undeploy from an environment
patch_release_binding(namespace, binding_name, overrides)      → update env overrides or release ref
```

> **No MCP tools** for `deploy_release` or `promote_component`. To promote to a downstream environment, `occ apply -f releasebinding.yaml` with the target environment, or patch the binding's `environment` field.

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

```
get_workload_schema(namespace, project, component)         → understand workload fields first
create_workload(namespace, project, component, name, spec) → create workload
update_workload(namespace, workload_name, spec)            → update existing workload
list_workloads(namespace, project, component)              → verify it appears
```

> `update_workload` takes only `namespace_name`, `workload_name`, `workload_spec` — not `project_name` or `component_name`. Use `list_workloads` to find the workload name first.

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

# 4. Apply workloads in batch
# Batch 1: workloads without dependencies (simpler, fewer failure modes)
# Batch 2: workloads with dependencies
occ apply -f /tmp/<app>-workloads.yaml
occ apply -f /tmp/<app>-workloads-dependencies.yaml

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

## Developer Gotchas

**TCP `address` binding injects `host:port`, not a protocol DSN**: For databases (PostgreSQL, MySQL) and message brokers (NATS, Redis), the injected `address` value is a plain `host:port` string. Apps that expect `postgres://user:pass@host/db` or `nats://host:4222` will fail to parse it. Declare the dependency for the topology diagram but set the full DSN as a literal env var instead. Get the hostname from `get_release_binding` → `endpoints[*].serviceURL.host`.

**Source-build workloads have no endpoints or dependencies until you add them**: The `generate-workload-cr` build step creates a minimal workload with just the image. If the repo has no `workload.yaml`, always call `update_workload` after a successful build to add endpoints, env vars, and dependencies. Without this the component deploys but has no routing, no dependencies, and the cell diagram renders incomplete.

**File mount `mountPath` is a directory**: The controller appends the `key` name to `mountPath` to form the final file path. Set `mountPath` to the parent directory (`/usr/share/nginx/html`), not the full file path (`/usr/share/nginx/html/config.json`). Using the full file path doubles the filename: `.../config.json/config.json`.

**Browser-facing apps need `https://` and `wss://` backend URLs**: OpenChoreo serves web-application components over HTTPS. Any backend URLs injected at runtime (e.g., via a mounted `config.json`) must use `https://` and `wss://`. HTTP/WS URLs are blocked by browsers as mixed content — no visible error, requests just silently fail. Always get external URLs from `get_release_binding` → `endpoints[*].externalURLs` and use the `https` scheme.
