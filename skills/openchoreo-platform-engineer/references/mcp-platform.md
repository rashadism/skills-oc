# OpenChoreo MCP — Platform Engineer Reference

PE workflows mapped to MCP tools. For the universal tool catalog, observability tools, and shared gotchas, see `openchoreo-core/references/mcp.md`.

> **MCP gaps for PE work — always use `occ apply -f` or `kubectl apply -f`:**
> - `create_environment` — no MCP tool; `occ apply -f`
> - `create_deployment_pipeline` — no MCP tool; **`kubectl apply -f`** (occ has a schema bug — see `cli-platform.md`)
> - DataPlane / WorkflowPlane / ObservabilityPlane CRUD — no MCP tools; `occ apply -f` or `kubectl apply -f`
>
> `create_project` MCP accepts a `deployment_pipeline` parameter — always pass it explicitly to avoid defaulting to `deploymentPipelineRef: default`.

## PE Workflows

### 1. Initial Platform Setup

Environments and DeploymentPipelines have no MCP create tools. Plane resources don't either. Use `occ apply -f` (see `cli-platform.md`).

```bash
# Step 1 — login to occ (local setup)
occ config controlplane update default --url http://api.openchoreo.localhost:8080
occ login    # browser-based PKCE auth

# Step 2 — create environments via occ apply
occ apply -f environment-development.yaml
occ apply -f environment-production.yaml

# Step 3 — create deployment pipeline via kubectl apply (occ has schema bug)
kubectl apply -f my-pipeline.yaml
```

Then create a project with the correct pipeline (preferred via MCP):

```
create_project(namespace, name, deployment_pipeline="my-pipeline")
```

Or via `occ apply -f project.yaml` if you also need annotations.

Verify with MCP:

```
list_environments(namespace)            → confirm environments visible
list_deployment_pipelines(namespace)    → confirm pipeline visible
list_projects(namespace)                → confirm pipeline assignments
```

### 2. Inspect Platform Infrastructure

```
list_namespaces                              → what namespaces exist?
list_environments(namespace)                 → what environments are available?
list_deployment_pipelines(namespace)         → what promotion paths exist?
get_deployment_pipeline(namespace, name)     → inspect pipeline spec
list_cluster_component_types(namespace)      → what component types are registered?
list_cluster_traits(namespace)               → what traits are registered?
list_workflows(namespace)                    → what build workflows exist?
```

For plane status (DataPlane, WorkflowPlane, ObservabilityPlane), use the REST API since there are no MCP tools:

```bash
# Get all dataplanes
curl -s -H "Authorization: Bearer $MCP_TOKEN" \
  "http://api.openchoreo.localhost:8080/api/v1/namespaces/default/dataplanes"

# If the REST API doesn't expose planes, kubectl is the fallback
kubectl get clusterdataplane,clusterworkflowplane,clusterobservabilityplane -A
```

### 3. Register Component Types

ComponentTypes and ClusterComponentTypes define the allowed workload shapes developers can deploy. Inspect before creating:

```
list_cluster_component_types(namespace)            → what types exist?
get_cluster_component_type(namespace, name)        → inspect one type
get_cluster_component_type_schema(namespace, name) → see full schema with templates
```

Register new types via `occ apply` (preferred) or the REST API. See `templates-and-workflows.md` for authoring detail.

### 4. Register Traits

Traits are capabilities (ingress, storage, etc.) that can be attached to components:

```
list_cluster_traits(namespace)              → what traits exist?
get_cluster_trait(namespace, name)          → inspect one trait
get_cluster_trait_schema(namespace, name)   → see full schema with patches
```

### 5. Register Workflow Templates

Build workflow templates define how components are built. Both cluster-scoped and namespace-scoped variants are supported:

```
list_cluster_workflows                        → cluster-scoped templates (shared across namespaces)
get_cluster_workflow(cwf_name)                → inspect full cluster workflow spec
get_cluster_workflow_schema(cwf_name)         → inspect parameter schema
list_workflows(namespace)                     → namespace-scoped templates
get_workflow_schema(namespace, name)          → inspect namespace workflow schema
```

Register new workflows via `occ apply` (preferred) or the REST API.

### 6. Inspect Tenant Usage

```
list_projects(namespace)                              → what projects exist?
list_components(namespace, project)                   → what components are deployed?
get_component(namespace, project, component)          → inspect spec and status conditions
list_environments(namespace)                          → what environments are active?
list_release_bindings(namespace, project, component)  → binding per environment
get_release_binding(namespace, binding_name)          → binding status, endpoints, state
list_workloads(namespace, project, component)         → running workloads
get_workload(namespace, workload_name)                → workload spec and status
list_secret_references(namespace)                     → available secrets
```

### 7. Validate Observability Stack

After registering an ObservabilityPlane, confirm data is flowing end-to-end:

```
query_resource_metrics(namespace, project, component, environment) → CPU/memory arriving?
query_component_logs(namespace, project, component, environment)   → logs arriving?
query_http_metrics(namespace, project, component, environment)     → HTTP metrics arriving?
query_traces(namespace, project, component, environment)           → traces arriving?
```

If any query returns no data, check the ObservabilityPlane agent connectivity and Helm configuration for that signal type. See `troubleshooting.md`.

## REST API for plane resources not exposed by MCP

For DataPlane, WorkflowPlane, and ObservabilityPlane reads when MCP doesn't cover them, mint a token and call the REST API:

```bash
MCP_TOKEN=$(curl -s -X POST "http://thunder.openchoreo.localhost:8080/oauth2/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -u 'service_mcp_client:service_mcp_client_secret' \
  -d 'grant_type=client_credentials' | jq -r '.access_token')

curl -s -H "Authorization: Bearer $MCP_TOKEN" \
  "http://api.openchoreo.localhost:8080/api/v1/namespaces/default/dataplanes"
```

Fall back to `kubectl` only if the REST API does not expose the resource.

## PE-Specific Gotchas

**`create_environment` and `create_deployment_pipeline` are not MCP tools**: Use `occ apply -f` (or `kubectl apply -f` for DeploymentPipeline due to the schema bug). See `cli-platform.md`.

**DataPlane / WorkflowPlane / ObservabilityPlane CRUD is not exposed via MCP or REST**: Use `occ apply -f <file>` if occ is available, otherwise `kubectl apply`. Helm values control plane registration at install time.

**Namespace-scoped vs cluster-scoped resources are not interchangeable**: `DataPlane`/`WorkflowPlane`/`ObservabilityPlane` come in both namespace-scoped and cluster-scoped (`ClusterDataPlane`, etc.) variants. Use cluster-scoped for shared infrastructure; namespace-scoped for tenant isolation.

**`get_cluster_component_type_schema` vs `get_component_type_schema`**: Cluster-scoped types (`ClusterComponentType`) are the most common. Namespace-scoped types (`ComponentType`) are for tenant isolation. Reach for the cluster-scoped tools first.

**No observability data after plane registration**: Inspect the ObservabilityPlane with `kubectl describe`. Missing data usually means the agent CA cert is wrong or `observerURL` is unreachable.

**`occ apply -f -` (stdin) does not work**: Write YAML to a temp file first.
