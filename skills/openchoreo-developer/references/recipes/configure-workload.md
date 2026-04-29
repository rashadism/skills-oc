# Configure a Workload

Add or change endpoints, environment variables, config files, and traits on a Component / Workload after the initial deploy. Most fields live on the Workload (`spec.container`, `spec.endpoints`); traits attach to the Component (`spec.traits[]`).

> **Tool surface preference: MCP first, `occ` CLI as fallback.** Same as every recipe in this skill.

## When to use

- The deployed Component needs more env vars, config files, ports, or endpoints
- A new Trait (autoscaler, alert rule, ingress override) needs to attach to the Component
- The Workload's `container.image` needs to change to a new tag (BYOI re-deploy)
- For per-environment overrides (different replicas in prod vs dev), use `recipes/override-per-environment.md` — those don't touch the base Workload
- For service-to-service connections, use `recipes/connect-components.md`
- For secrets specifically, use `recipes/manage-secrets.md`

## Prerequisites

A Component and Workload already exist. If not, see `recipes/deploy-prebuilt-image.md` or `recipes/build-from-source.md` first.

## Recipe — MCP (preferred)

### 1. Read the current Workload

```
mcp__openchoreo-cp__get_workload
  namespace_name: default
  workload_name: greeter-workload
```

If unsure of the spec shape:

```
mcp__openchoreo-cp__get_workload_schema
  (no parameters)
```

### 2. Update the Workload

Edit the spec locally, then send the full updated `workload_spec`:

```
mcp__openchoreo-cp__update_workload
  namespace_name: default
  workload_name: greeter-workload
  workload_spec:
    owner:
      projectName: default
      componentName: greeter
    container:
      image: ghcr.io/openchoreo/samples/greeter-service:v2
      env:
        - key: LOG_LEVEL
          value: debug
        - key: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
      files:
        - key: app.yaml
          mountPath: /etc/config
          value: |
            server:
              port: 8080
    endpoints:
      http:
        type: HTTP
        port: 9090
        visibility: [external]
        basePath: /api/v1
      grpc:
        type: gRPC
        port: 9091
        visibility: [namespace]
```

`update_workload` sends the full `workload_spec`, not a partial patch — read first, modify locally, send back.

A new ComponentRelease is generated automatically; `auto_deploy: true` (set on the Component) triggers redeploy to the first environment.

### 3. Attach a Trait to the Component

There is no MCP tool to update a Component's `spec.traits[]`. Trait attachment goes through `occ apply -f` against an updated Component YAML — see the CLI fallback section.

For trait *parameter* overrides per environment (without changing the Component itself), use `update_release_binding` with `trait_environment_configs` — see `recipes/override-per-environment.md`.

To discover available traits before attaching:

```
mcp__openchoreo-cp__list_cluster_traits
mcp__openchoreo-cp__get_cluster_trait_schema
  ct_name: observability-alert-rule
```

### 4. Verify

```
mcp__openchoreo-cp__get_release_binding
  namespace_name: default
  binding_name: <name from list_release_bindings>
```

Check `status.conditions[]` for `Ready: True`, `Deployed: True`, `Synced: True`. For runtime logs, see `recipes/inspect-and-debug.md`.

## Recipe — `occ` CLI (fallback)

### 1. Read the current spec

```bash
occ workload get greeter-workload --namespace default
occ component get greeter --namespace default
```

### 2. Edit and apply

Edit the YAML locally, then:

```bash
occ apply -f /tmp/workload.yaml
occ apply -f /tmp/component.yaml      # if attaching a Trait or changing ComponentType
```

### 3. Verify

```bash
occ releasebinding list --namespace default --project default --component greeter
occ component logs greeter --namespace default
```

## Configuration patterns

### Endpoints

```yaml
endpoints:
  http:
    type: HTTP                       # HTTP | gRPC | GraphQL | Websocket | TCP | UDP
    port: 8080                       # container listening port
    targetPort: 8080                 # optional, defaults to port
    visibility: [external]           # [project]+[namespace]+[internal]+[external] — list any combination
    basePath: /api/v1                # optional, HTTP-only
    displayName: REST API            # optional
    schema: {}                       # optional OpenAPI spec object
```

Visibility levels (broader → narrower):

| Level | Reachable from |
|---|---|
| `external` | Public internet, via gateway |
| `internal` | Anywhere inside the deployment topology |
| `namespace` | All projects in same namespace + environment |
| `project` | Same project + environment (implicit if no level given) |

Visibility is a list — an endpoint can expose itself at multiple levels at once (e.g. `[namespace, external]`).

### Environment variables

```yaml
container:
  env:
    - key: LOG_LEVEL
      value: info                                   # literal
    - key: DB_PASSWORD
      valueFrom:
        secretKeyRef:                               # reference a SecretReference
          name: db-secret
          key: password
```

Each entry needs **exactly one** of `value` or `valueFrom`. For SecretReference setup, see `recipes/manage-secrets.md`. For dependency-injected env vars (service URLs of other components), see `recipes/connect-components.md`.

### Configuration files

```yaml
container:
  files:
    - key: config.yaml
      mountPath: /etc/config
      value: |                                      # literal content
        server:
          port: 8080
    - key: tls.crt
      mountPath: /etc/tls
      valueFrom:
        secretKeyRef:                               # from SecretReference
          name: tls-certs
          key: certificate
    - key: app.conf
      mountPath: /etc/app
      valueFrom:
        path: configs/app.conf                      # source-build only — file in repo, relative to workload.yaml
```

`valueFrom.path` is build-time only — applies when the source-build flow generates the Workload from `workload.yaml` in the repo. It does not work for BYOI Workloads (the runtime has no access to the repo).

### Resources and replicas

These usually live in the **Component's `parameters`** field, not the Workload:

```yaml
spec:
  parameters:
    replicas: 2
    resources:
      requests: {cpu: 100m, memory: 128Mi}
      limits:   {cpu: 500m, memory: 512Mi}
```

The exact parameter set depends on the ClusterComponentType — discover with `mcp__openchoreo-cp__get_cluster_component_type_schema cct_name: deployment/service`.

For per-environment differences (more replicas in prod), override at the ReleaseBinding level — see `recipes/override-per-environment.md`.

### Traits

```yaml
spec:
  traits:
    - kind: ClusterTrait                            # required — defaults to namespace-scoped Trait
      name: observability-alert-rule
      instanceName: high-error-rate                 # unique per Component
      parameters:
        severity: critical
        source: {type: log, query: "status:error"}
        condition: {window: 5m, operator: gt, threshold: 50}
```

Discover available traits via `mcp__openchoreo-cp__list_cluster_traits`. Get a trait's parameter schema via `mcp__openchoreo-cp__get_cluster_trait_schema`.

For the `observability-alert-rule` trait specifically, see `recipes/attach-alerts.md`.

## Gotchas

- **`update_workload` sends the full spec, not a partial patch.** Always `get_workload` first, modify locally, send the complete `workload_spec`. Omitting a field deletes it.
- **`env` and `files` entries need exactly one of `value` or `valueFrom`** — not both, not neither. Validation fails otherwise.
- **`valueFrom.path` only works in source-build `workload.yaml`** at build time. For BYOI, use literal `value` or `valueFrom.secretKeyRef`.
- **`componentType.kind` and `traits[].kind` default wrong.** Both default to namespace-scoped (`ComponentType` / `Trait`). Built-ins are cluster-scoped (`ClusterComponentType` / `ClusterTrait`). Always set `kind` explicitly.
- **No MCP tool for Component updates.** Trait attachment, ComponentType changes, and `parameters` edits go through `occ apply -f` against an updated Component YAML.
- **Visibility on a dependency must be ≤ visibility on the target endpoint.** A consumer asking for `namespace` visibility against a target that only declares `project` visibility fails. See `recipes/connect-components.md` for the dependency rules.
- **Updating the Workload triggers a new ComponentRelease and (if `auto_deploy: true`) redeploys to the first environment.** Subsequent environments are not promoted automatically — see `recipes/deploy-and-promote.md`.

## Related recipes

- [`deploy-prebuilt-image.md`](deploy-prebuilt-image.md) — initial BYOI deploy
- [`build-from-source.md`](build-from-source.md) — source-build deploy (uses `workload.yaml` at build time)
- [`connect-components.md`](connect-components.md) — endpoint dependencies
- [`manage-secrets.md`](manage-secrets.md) — SecretReference patterns
- [`override-per-environment.md`](override-per-environment.md) — per-env replicas / resources / traits / env
- [`attach-alerts.md`](attach-alerts.md) — observability-alert-rule trait
- [`inspect-and-debug.md`](inspect-and-debug.md) — verify the change took effect
