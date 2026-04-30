# Deploy a pre-built image (BYOI)

Deploy an existing container image — built elsewhere or pulled from a public/private registry — as a Component on OpenChoreo. No source build, no workflow.

## When to use

- The user has an image reference (`registry/repo:tag`) and wants it running
- Deploying a third-party / off-the-shelf service (databases, OSS apps, vendor images)
- The dev does not want OpenChoreo to build their image
- For source-build (Component built from a Git repo), see `recipes/build-from-source.md` instead

## Prerequisites

1. The control-plane MCP server is configured and reachable (`list_namespaces` returns).
2. A Project exists. The `default` project is created during install — confirm with `list_projects` (`namespace_name: default`). If you need a new one, see [Variant: create a Project](#variant-create-a-project) below.
3. A ClusterComponentType matching the workload shape exists — discover with `list_cluster_component_types`. Common ones: `deployment/service`, `deployment/web-application`, `deployment/worker`, `cronjob/scheduled-task`.

## Recipe

### 1. Create the Component

```
create_component
  namespace_name: default
  project_name: default
  name: greeter
  component_type: deployment/service        # one string, "{workloadType}/{name}"
  auto_deploy: true                          # creates ReleaseBinding for first env
```

**Do not pass `workflow`** — that turns this into a source build.

### 2. Inspect the Workload schema

If you're not sure of the workload spec shape, fetch the schema first:

```
get_workload_schema
  (no parameters)
```

Returns the JSON schema for `workload_spec`, including `container`, `endpoints`, `dependencies`, and validation rules.

### 3. Create the Workload

```
create_workload
  namespace_name: default
  component_name: greeter
  workload_spec:
    owner:
      projectName: default
      componentName: greeter
    container:
      image: ghcr.io/openchoreo/samples/greeter-service:latest
      env:
        - key: LOG_LEVEL
          value: info
    endpoints:
      http:
        type: HTTP
        port: 9090
        visibility: [external]
```

For env vars, file mounts, and endpoint shapes beyond the basics, see `recipes/configure-workload.md`.

### 4. Verify

```
get_component
  namespace_name: default
  component_name: greeter
```

```
list_release_bindings
  namespace_name: default
  component_name: greeter
```

```
get_release_binding
  namespace_name: default
  binding_name: <name from list above>
```

The deployed URL is in `status.endpoints` of the ReleaseBinding — read it from there, do not construct it by hand.

For runtime logs:

```
query_component_logs
  namespace: default
  component: greeter
  start_time: <RFC3339, e.g. 2026-04-29T00:00:00Z>
  end_time:   <RFC3339, e.g. 2026-04-29T01:00:00Z>
```

For deeper inspection (k8s artifacts, status conditions, crashloop debug), see `recipes/inspect-and-debug.md`.

## Variant: create a Project

When the existing `default` project doesn't fit (separate pipeline, ownership boundary):

```
create_project
  namespace_name: default
  name: online-store
  description: "E-commerce application components"
  deployment_pipeline: default              # optional, defaults to "default"
```

> Deleting a Project deletes every Component inside it. There is no MCP `delete_project` tool — hard-delete needs `openchoreo-platform-engineer`. Confirm with the user before escalating.

Then change `project_name` on your Component and Workload calls to the new project name.

## Variant: pull from a private registry

The developer-side input is identical — just point `image` at the private repo.

```
create_workload
  ...
  workload_spec:
    container:
      image: docker.io/<org>/<repo>:<tag>
    ...
```

The auth itself is **PE-owned**, not a per-Component setting. The platform must:
- store registry credentials in the secret backend (e.g. OpenBao);
- have a `ClusterComponentType` whose template generates an `ExternalSecret` of type `kubernetes.io/dockerconfigjson` and references it from `spec.template.spec.imagePullSecrets`.

If a private image fails with `ImagePullBackOff` after deploy, the platform side is missing one of those — escalate via `openchoreo-platform-engineer` rather than patching the Component.

## Gotchas

- **`component_type` is a single string in `{workloadType}/{name}` form**, not a separate kind+name pair. The MCP call constructs the underlying `componentType.kind: ClusterComponentType` reference (built-ins are cluster-scoped).
- **For BYOI, do not pass `workflow` to `create_component`.** Adding a workflow turns this into a source build and triggers failed builds.
- **For BYOI, you create the Workload yourself** via `create_workload`. Source-build components auto-generate `{component}-workload`; never call `create_workload` for those. BYOI is the opposite.
- **Workload `owner` (projectName + componentName) is immutable** after creation. Pick names carefully.
- **`env` and `files` entries need exactly one of `value` or `valueFrom`** — not both, not neither. Validation fails otherwise.
- **`auto_deploy: true` only deploys to the first environment** in the pipeline. Promotion to staging/prod uses `create_release_binding` for each subsequent environment — see `recipes/deploy-and-promote.md`.
- **Trust ReleaseBinding status for the deployed URL.** Don't construct hostnames from the Component name and an environment guess — gateway routes vary by deployment topology.

## Related recipes

- [`configure-workload.md`](configure-workload.md) — env vars, config files, endpoint visibility, traits
- [`connect-components.md`](connect-components.md) — declare endpoint dependencies on other components
- [`manage-secrets.md`](manage-secrets.md) — SecretReference + secret-referenced env vars
- [`deploy-and-promote.md`](deploy-and-promote.md) — promote to next environment, rollback
- [`inspect-and-debug.md`](inspect-and-debug.md) — logs, status, k8s artifacts
- [`build-from-source.md`](build-from-source.md) — alternative path: build the image from a Git repo
