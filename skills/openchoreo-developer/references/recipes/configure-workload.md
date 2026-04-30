# Configure a Workload

Add or change endpoints, environment variables, config files, and traits on a Component / Workload after the initial deploy. Most fields live on the Workload (`spec.container`, `spec.endpoints`); traits attach to the Component (`spec.traits[]`).

## When to use

- The deployed Component needs more env vars, config files, ports, or endpoints
- A new Trait (autoscaler, alert rule, ingress override) needs to attach to the Component
- The Workload's `container.image` needs to change to a new tag (BYOI re-deploy)
- For per-environment overrides (different replicas in prod vs dev), use `recipes/override-per-environment.md` — those don't touch the base Workload
- For service-to-service connections, use `recipes/connect-components.md`
- For secrets specifically, use `recipes/manage-secrets.md`

## Prerequisites

A Component and Workload already exist. If not, see `recipes/deploy-prebuilt-image.md` or `recipes/build-from-source.md` first.

## Recipe

### 1. Read the current Workload

```
get_workload
  namespace_name: default
  workload_name: greeter-workload
```

If unsure of the spec shape:

```
get_workload_schema
  (no parameters)
```

### 2. Update the Workload

Edit the spec locally, then send the full updated `workload_spec`:

```
update_workload
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

**No MCP write surface for `spec.traits[]` attachment** — `patch_component` does not cover trait edits. Hand off to `openchoreo-platform-engineer` to apply an updated Component spec with the new trait entry.

For trait *parameter* overrides per environment (without changing the Component itself), use `update_release_binding` with `trait_environment_configs` — see `recipes/override-per-environment.md`. That stays in this skill.

To discover available traits before attaching:

```
list_cluster_traits
get_cluster_trait_schema
  ct_name: observability-alert-rule
```

### 4. Verify

```
get_release_binding
  namespace_name: default
  binding_name: <name from list_release_bindings>
```

Check `status.conditions[]` for `Ready: True`, `Deployed: True`, `Synced: True`. For runtime logs, see `recipes/inspect-and-debug.md`.

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

In a Workload CR (sent via `update_workload`):

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
```

> **Field naming differs between Workload CR and `workload.yaml` descriptor.** The Workload CR (this recipe's MCP path) uses `container.env[]` / `container.files[]` with `key:`. The `workload.yaml` descriptor in the source repo uses `configurations.env[]` / `configurations.files[]` with `name:` instead of `key:`. The descriptor also supports `valueFrom.path: <repo-relative path>` to inline a file from the repo at build time — that's descriptor-only; the runtime Workload CR has no repo access.

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

The exact parameter set depends on the ClusterComponentType — discover with `get_cluster_component_type_schema cct_name: deployment/service`.

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

Discover available traits via `list_cluster_traits`. Get a trait's parameter schema via `get_cluster_trait_schema`.

For the `observability-alert-rule` trait specifically, see `recipes/attach-alerts.md`.

## Gotchas

- **`update_workload` sends the full spec, not a partial patch.** Always `get_workload` first, modify locally, send the complete `workload_spec`. Omitting a field deletes it.
- **`env` and `files` entries need exactly one of `value` or `valueFrom`** — not both, not neither. Validation fails otherwise.
- **Workload CR uses `key:`; `workload.yaml` descriptor uses `name:`** under `configurations.env[]` / `configurations.files[]`. Easy to mix up when copy-pasting between recipes.
- **`valueFrom.path` only works in source-build `workload.yaml`** at build time. For Workload CRs (BYOI or post-build update via MCP), use literal `value` or `valueFrom.secretKeyRef`.
- **`componentType.kind` and `traits[].kind` default wrong.** Both default to namespace-scoped (`ComponentType` / `Trait`). Built-ins are cluster-scoped (`ClusterComponentType` / `ClusterTrait`). Always set `kind` explicitly.
- **No MCP write surface for Component trait attachment / ComponentType changes / `spec.parameters` edits.** Hand those off to `openchoreo-platform-engineer`.
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
