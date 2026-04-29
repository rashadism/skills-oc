# Deploy and promote

Deploy a Component release to its first environment and promote it through the pipeline (e.g. `development → staging → production`). Also: rollback to an older release, undeploy, and redeploy an undeployed binding.

> **Tool surface preference: MCP first, `occ` CLI as fallback.** Same as every recipe in this skill.

## When to use

- A new Component release is ready and needs to reach the first environment
- A working release needs to move from one environment to the next
- A bad release needs to roll back to an earlier known-good one
- A binding needs to be temporarily removed (`Undeploy`) without losing its config
- An undeployed binding needs to be re-activated

## How releases and bindings relate

```
Component + Workload
        ↓
ComponentRelease (immutable snapshot, named like {component}-<hash>)
        ↓
ReleaseBinding (one per environment — what's actually deployed there)
        ↓
Deployment + Service + HTTPRoute (in the data plane)
```

`auto_deploy: true` on the Component creates the **first environment's** ReleaseBinding automatically when a new ComponentRelease appears. Subsequent environments are manual.

To list releases:

```bash
occ componentrelease list --namespace default --project default --component my-service
```

To list current bindings:

```
mcp__openchoreo-cp__list_release_bindings
  namespace_name: default
  component_name: my-service
```

## Recipe — first environment

If `auto_deploy: true` was set on `create_component`, the first environment's ReleaseBinding is created automatically when the ComponentRelease lands. Skip ahead to verification.

If `auto_deploy: false` (or you want explicit control), create the binding manually.

### MCP

```
mcp__openchoreo-cp__create_release_binding
  namespace_name: default
  project_name: default
  component_name: my-service
  environment: development
  release_name: my-service-5d7f658d9c     # from `occ componentrelease list`
```

### CLI

```bash
occ component deploy my-service --namespace default --project default
```

For a specific release (instead of latest):

```bash
occ component deploy my-service --release my-service-5d7f658d9c
```

### Verify

```
mcp__openchoreo-cp__get_release_binding
  namespace_name: default
  binding_name: my-service-development
```

`status.conditions[]` should show `Ready: True`, `Deployed: True`, `Synced: True`. Read the deployed URL from `status.endpoints[]`.

## Recipe — promote to next environment

Promotion is "create a new ReleaseBinding for the next environment, pointing at the same release." Pipelines define the allowed source → target paths; the platform validates against them.

### MCP

```
mcp__openchoreo-cp__create_release_binding
  namespace_name: default
  project_name: default
  component_name: my-service
  environment: staging
  release_name: my-service-5d7f658d9c     # same release that's running in dev
```

For per-environment overrides at promotion time, see `recipes/override-per-environment.md` — pass `component_type_environment_configs`, `trait_environment_configs`, and `workload_overrides` on the same call.

### CLI

```bash
occ component deploy my-service --to staging
occ component deploy my-service --to production
```

`--to` resolves the target environment from the Component's deployment pipeline. To promote a *specific* release rather than the latest:

```bash
occ component deploy my-service --to staging --release my-service-5d7f658d9c
```

### Verify

```
mcp__openchoreo-cp__list_release_bindings
  namespace_name: default
  component_name: my-service
```

Confirm a binding now exists for `staging` with the expected `release_name`. Then check status as above.

## Variant — rollback to a previous release

Rollback = point an existing ReleaseBinding at an older ComponentRelease. The release stays in the registry forever (releases are immutable); only the binding's `release_name` changes.

### Find the older release

```bash
occ componentrelease list --namespace default --project default --component my-service
```

The output lists all releases for the component, oldest to newest.

### MCP

```
mcp__openchoreo-cp__update_release_binding
  namespace_name: default
  binding_name: my-service-production
  release_name: my-service-a1b2c3d4e5     # the older release to roll back to
```

### CLI

```bash
occ component deploy my-service --to production --release my-service-a1b2c3d4e5
```

### Verify

`status.conditions[]` flips through `Synced: False` while the new release rolls out, then back to `Synced: True`. Watch logs to confirm the older code is running:

```
mcp__openchoreo-obs__query_component_logs
  namespace: default
  component: my-service
  environment: production
  start_time: <RFC3339>
  end_time:   <RFC3339>
```

## Variant — undeploy

Take a binding offline without deleting it. Config (overrides, release pointer) stays intact for a future redeploy.

### MCP

```
mcp__openchoreo-cp__update_release_binding_state
  namespace_name: default
  binding_name: my-service-staging
  release_state: Undeploy
```

Valid `release_state` values: `Active`, `Undeploy`.

The Deployment, Service, and HTTPRoute in the data plane disappear; the ReleaseBinding resource itself stays. Re-activating restores them with the same config.

## Variant — redeploy an undeployed binding

```
mcp__openchoreo-cp__update_release_binding_state
  namespace_name: default
  binding_name: my-service-staging
  release_state: Active
```

The Deployment / Service / HTTPRoute come back with the binding's existing release and overrides. To redeploy with a *different* release at the same time, do this first then `update_release_binding release_name: <new>`.

## Gotchas

- **`auto_deploy` only auto-creates the *first* environment's binding.** Promotion to staging/prod is always manual or via GitOps.
- **Releases are immutable.** Once a ComponentRelease exists, its image and Workload spec are frozen. You cannot "edit" a release — make a new ComponentRelease (by updating the Workload) and point the binding at it.
- **`create_release_binding` fails if a binding already exists for that environment.** To change the release in an existing binding, use `update_release_binding release_name: <new>`. The MCP tool description says this explicitly.
- **Pipelines gate promotion paths.** If the pipeline only allows `dev → staging → prod`, you cannot skip from `dev → prod` directly. Override at the PE side or change the pipeline.
- **Promoted bindings start without overrides.** Each environment's ReleaseBinding is independent — promotion creates a fresh binding for the new env. Re-apply per-environment overrides explicitly. See `recipes/override-per-environment.md`.
- **`Undeploy` does not delete the binding.** It just removes the data-plane resources. The ReleaseBinding resource is still there with all config intact. To fully delete, use `delete_release_binding` (MCP) or `occ releasebinding delete`.
- **Rollback only changes `release_name`** — env-specific overrides on the binding survive. If the older release expected different env vars, you may need to also update `workload_overrides` on the same call.
- **`occ component deploy --to <env>` infers the latest release.** To roll back via CLI, always pass `--release <name>` explicitly, otherwise you'll redeploy the latest (which is what you're rolling back from).

## Related recipes

- [`override-per-environment.md`](override-per-environment.md) — overrides applied at promotion time
- [`inspect-and-debug.md`](inspect-and-debug.md) — verify the new release deployed cleanly
- [`configure-workload.md`](configure-workload.md) — changing the base Workload generates a new release
- [`deploy-prebuilt-image.md`](deploy-prebuilt-image.md) / [`build-from-source.md`](build-from-source.md) — produce the releases you'll promote
