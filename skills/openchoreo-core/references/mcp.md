# OpenChoreo MCP — Foundational Reference

OpenChoreo exposes two MCP servers. Use these tools instead of the `occ` CLI when working through an AI assistant.

| Server | Tool prefix | Purpose |
|---|---|---|
| Control plane | `mcp__openchoreo-cp__*` | Resource CRUD, schemas, workflows, releases |
| Observability | `mcp__openchoreo-obs__*` | Logs, metrics, traces, spans |

Both must be configured separately; neither covers the other's surface.

For workflow-specific MCP detail (deploy flows, third-party app workflows, plane registration, etc.) see:
- Application work — `openchoreo-developer/references/mcp-developer.md`
- Platform engineering — `openchoreo-platform-engineer/references/mcp-platform.md`

## Control plane tool catalog

| MCP Tool | CLI Equivalent | Purpose |
|---|---|---|
| `list_namespaces` | `occ namespace list` | List all namespaces |
| `create_namespace` | `occ apply -f namespace.yaml` | Create a namespace |
| `list_projects` | `occ project list` | List projects in a namespace |
| `create_project` | `occ apply -f project.yaml` | Create a new project (accepts `deployment_pipeline` parameter) |
| `list_components` | `occ component list` | List components in a project |
| `get_component` | `occ component get <name>` | Get component spec and status |
| `create_component` | `occ apply -f component.yaml` | Create a new component |
| `patch_component` | `occ apply -f component.yaml` (update) | Patch component fields |
| `get_component_schema` | `occ component scaffold` (inspect) | Get component YAML schema |
| `list_component_types` | `occ componenttype list` | List namespace-scoped component types |
| `get_component_type_schema` | `occ componenttype get <name>` | Get component type schema |
| `list_cluster_component_types` | `occ clustercomponenttype list` | List cluster-scoped component types |
| `get_cluster_component_type` | `occ clustercomponenttype get <name>` | Get cluster component type |
| `get_cluster_component_type_schema` | `occ clustercomponenttype get <name>` | Get cluster component type schema |
| `list_traits` | `occ trait list` | List namespace-scoped traits |
| `get_trait_schema` | `occ trait get <name>` | Get trait schema |
| `list_cluster_traits` | `occ clustertrait list` | List cluster-scoped traits |
| `get_cluster_trait` | `occ clustertrait get <name>` | Get cluster trait |
| `get_cluster_trait_schema` | `occ clustertrait get <name>` | Get cluster trait schema |
| `list_workflows` | `occ workflow list` | List namespace-scoped workflow templates |
| `get_workflow_schema` | `occ workflow get <name>` | Get workflow template schema |
| `list_cluster_workflows` | `occ clusterworkflow list` | List cluster-scoped workflow templates |
| `get_cluster_workflow` | `occ clusterworkflow get <name>` | Get full cluster workflow spec |
| `get_cluster_workflow_schema` | `occ clusterworkflow get <name>` | Get cluster workflow parameter schema |
| `create_workflow_run` | `occ component workflow run` | Queue a workflow run with explicit parameters |
| `trigger_workflow_run` | `occ component workflow run <name>` | Trigger a build for a component using its configured workflow |
| `get_workflow_run` | `occ component workflowrun get <name>` | Get a specific workflow run |
| `list_workflow_runs` | `occ component workflowrun list` | List workflow run history |
| `create_workload` | `occ workload create` | Create a workload for a BYO-image component |
| `update_workload` | `occ apply -f workload.yaml` (update) | Update an existing workload |
| `get_workload` | `occ workload get <name>` | Get workload details |
| `get_workload_schema` | — | Get workload YAML schema |
| `list_workloads` | `occ workload list --component <name>` | List workloads for a component |
| `list_environments` | `occ environment list` | List environments |
| `list_deployment_pipelines` | `occ deploymentpipeline list` | List deployment pipelines |
| `get_deployment_pipeline` | `occ deploymentpipeline get <name>` | Get deployment pipeline details |
| `list_release_bindings` | `occ releasebinding list` | List release bindings |
| `get_release_binding` | `occ releasebinding get <name>` | Get a specific release binding |
| `patch_release_binding` | `occ apply -f releasebinding.yaml` (update) | Patch a release binding (overrides, env, release) |
| `update_release_binding_state` | — | Set release binding state: `Active` or `Undeploy` |
| `list_secret_references` | `occ secretreference list` | List secret references |

> **No MCP tools** for `create_environment`, `create_deployment_pipeline`, `deploy_release`, `promote_component`, or plane CRUD. Use `occ apply -f` for these — see the workflow-specific MCP references for the full pattern.

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

## Universal Exploration Workflow

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

## Universal MCP Gotchas

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

**Two separate MCP servers**: `mcp__openchoreo-cp__*` (control plane) and `mcp__openchoreo-obs__*` (observability) — both must be configured.

**`update_workload` only takes `namespace_name`, `workload_name`, `workload_spec`**: It does not accept `project_name` or `component_name`. Use `list_workloads` to find the workload name first.

**Observability data requires a live ObservabilityPlane**: If queries return no data, the plane may be missing or unhealthy. Escalate to `openchoreo-platform-engineer`.
