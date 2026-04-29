# Deploy a pre-built image (BYOI)

Deploy an existing container image — built elsewhere or pulled from a public/private registry — as a Component on OpenChoreo. No source build, no workflow.

> **Tool surface preference: MCP first, `occ` CLI as fallback.** All recipes show MCP as the primary path. Use `occ` only for steps with no MCP equivalent (auth, scaffold, raw `apply -f`) or as a fallback when MCP fails.

## When to use

- The user has an image reference (`registry/repo:tag`) and wants it running
- Deploying a third-party / off-the-shelf service (databases, OSS apps, vendor images)
- The dev does not want OpenChoreo to build their image
- For source-build (Component built from a Git repo), see `recipes/build-from-source.md` instead

## Prerequisites

1. Logged in to the control plane. `occ` is required for auth even on the MCP path:
   ```bash
   occ version
   occ config context list      # active context marked with *
   ```
   No MCP equivalent for login — see `references/cli.md` for `occ login` and context setup.
2. A Project exists. The `default` project is created during install:
   - **MCP:** `mcp__openchoreo-cp__list_projects` with `namespace_name: default`
   - **CLI:** `occ project list --namespace default`
   - If you need a new one, see [Variant: create a Project](#variant-create-a-project) below.
3. A ClusterComponentType matching the workload shape exists:
   - **MCP:** `mcp__openchoreo-cp__list_cluster_component_types`
   - **CLI:** `occ clustercomponenttype list`

   Common ones: `deployment/service`, `deployment/web-application`, `deployment/worker`, `cronjob/scheduled-task`.

## Recipe — MCP (preferred)

### 1. Create the Component

```
mcp__openchoreo-cp__create_component
  namespace_name: default
  project_name: default
  name: greeter
  component_type: deployment/service        # one string, "{workloadType}/{name}"
  auto_deploy: true                          # creates ReleaseBinding for first env
```

**Do not pass `workflow`** — that turns this into a source build.

### 2. Inspect the Workload schema (optional but recommended)

If you're not sure of the workload spec shape, fetch the schema first:

```
mcp__openchoreo-cp__get_workload_schema
  (no parameters)
```

Returns the JSON schema for `workload_spec`, including `container`, `endpoints`, `dependencies`, and validation rules.

### 3. Create the Workload

```
mcp__openchoreo-cp__create_workload
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
mcp__openchoreo-cp__get_component
  namespace_name: default
  component_name: greeter
```

```
mcp__openchoreo-cp__list_release_bindings
  namespace_name: default
  component_name: greeter
```

```
mcp__openchoreo-cp__get_release_binding
  namespace_name: default
  binding_name: <name from list above>
```

The deployed URL is in `status.endpoints` of the ReleaseBinding — read it from there, do not construct it by hand.

For runtime logs:

```
mcp__openchoreo-obs__query_component_logs
  namespace: default
  component: greeter
  start_time: <RFC3339, e.g. 2026-04-29T00:00:00Z>
  end_time:   <RFC3339, e.g. 2026-04-29T01:00:00Z>
```

For deeper inspection (k8s artifacts, status conditions, crashloop debug), see `recipes/inspect-and-debug.md`.

## Recipe — `occ` CLI (fallback)

Use when MCP is unavailable, when the user explicitly asks for CLI, or when applying a complete YAML file from disk is preferable to building MCP call payloads by hand.

### 1. Author or scaffold the YAML

Either copy and edit the bundled template:

```bash
cp <skill-root>/assets/byoi-component-workload.yaml /tmp/app.yaml
# edit <COMPONENT_NAME>, image, port, etc.
```

Or scaffold from the live cluster:

```bash
occ component scaffold greeter \
  --clustercomponenttype deployment/service \
  --namespace default \
  --project default \
  -o /tmp/greeter.yaml
```

The scaffold output is two files (Component, Workload). Edit the Workload's `container.image` before applying.

### 2. Apply

```bash
occ apply -f /tmp/app.yaml
```

> `occ apply -f -` (stdin) does not work — file path required.

### 3. Verify

```bash
occ component get greeter --namespace default
occ releasebinding list --namespace default --project default --component greeter
occ component logs greeter --namespace default
```

## Variant: create a Project

When the existing `default` project doesn't fit (separate pipeline, ownership boundary):

**MCP:**
```
mcp__openchoreo-cp__create_project
  namespace_name: default
  name: online-store
  description: "E-commerce application components"
  deployment_pipeline: default              # optional, defaults to "default"
```

**CLI:** copy `assets/project.yaml`, set `<PROJECT_NAME>`, then:
```bash
occ apply -f /tmp/project.yaml
occ project list --namespace default
```

> Deleting a Project deletes every Component inside it. Confirm with the user before `occ project delete` or `mcp__openchoreo-cp__delete_project`.

Then change `project_name` (MCP) / `spec.owner.projectName` (YAML) on your Component and Workload to the new project name.

## Variant: pull from a private registry

The developer-side input is identical — just point `image` at the private repo.

**MCP:**
```
mcp__openchoreo-cp__create_workload
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

- **`component_type` (MCP) is a single string in `{workloadType}/{name}` form**, not a separate kind+name pair. For YAML, `componentType.kind: ClusterComponentType` is required (defaults to namespace-scoped `ComponentType` otherwise — built-ins are cluster-scoped).
- **For BYOI, do not pass `workflow` to `create_component` and do not include `spec.workflow` in YAML.** Adding a workflow turns this into a source build and triggers failed builds.
- **For BYOI, you create the Workload yourself** via `create_workload` or YAML. Source-build components auto-generate `{component}-workload`; never call `create_workload` for those. BYOI is the opposite.
- **Workload `owner` (projectName + componentName) is immutable** after creation. Pick names carefully.
- **`env` and `files` entries need exactly one of `value` or `valueFrom`** — not both, not neither. Validation fails otherwise.
- **`auto_deploy: true` only deploys to the first environment** in the pipeline. Promotion to staging/prod uses `create_release_binding` for each subsequent environment — see `recipes/deploy-and-promote.md`.
- **Trust ReleaseBinding status for the deployed URL.** Don't construct hostnames from the Component name and an environment guess — gateway routes vary by deployment topology.
- **`occ login --client-credentials` does not work with `service_mcp_client`** (`unauthorized_client`). Use browser-based `occ login`.
- **`occ apply -f -` (stdin) does not work** — file path required.

## Related recipes

- [`configure-workload.md`](configure-workload.md) — env vars, config files, endpoint visibility, traits
- [`connect-components.md`](connect-components.md) — declare endpoint dependencies on other components
- [`manage-secrets.md`](manage-secrets.md) — SecretReference + secret-referenced env vars
- [`deploy-and-promote.md`](deploy-and-promote.md) — promote to next environment, rollback
- [`inspect-and-debug.md`](inspect-and-debug.md) — logs, status, k8s artifacts
- [`build-from-source.md`](build-from-source.md) — alternative path: build the image from a Git repo
