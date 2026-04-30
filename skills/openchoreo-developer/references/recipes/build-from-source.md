# Build from source

Build a container image from a Git repository using a CI workflow, then deploy it as a Component. The workflow clones the repo, runs the configured builder (Dockerfile / buildpacks / Ballerina), pushes the image, and auto-generates a Workload from the build output.

## When to use

- The user wants OpenChoreo to build their image from source
- The repo has a Dockerfile, buildpack-compatible source, or Ballerina code
- For deploying an already-built image, see `recipes/deploy-prebuilt-image.md` instead

## Prerequisites

1. The control-plane MCP server is configured and reachable (`list_namespaces` returns).
2. A Project exists (see [Create a Project](deploy-prebuilt-image.md#variant-create-a-project)).
3. The repo URL, branch, and the path to the app inside the repo (`appPath`) are known.
4. The ClusterComponentType you'll use lists the workflow you want in `allowedWorkflows`. Discover with `list_cluster_component_types`, then `get_cluster_component_type` to read `allowedWorkflows`.

## Available builders

| ClusterWorkflow name | Builder | Builder-specific parameters |
|---|---|---|
| `dockerfile-builder` | Dockerfile / Containerfile | `docker.context`, `docker.filePath` |
| `gcp-buildpacks-builder` | Google Cloud buildpacks (Go, Java, Node, Python, .NET) | `buildEnv` (optional) |
| `paketo-buildpacks-builder` | Paketo buildpacks (Java, Node, Python, Go, .NET, Ruby, PHP) | `buildEnv` (optional) |
| `ballerina-buildpack-builder` | Ballerina | `buildEnv` (optional) |

All workflows share `repository.url`, `repository.revision.branch`, `repository.revision.commit` (optional), `repository.appPath`, and `repository.secretRef` (for private repos).

## Recipe

### 1. Pick a workflow and inspect its schema

```
list_cluster_workflows
```

Pick one, then read the parameter schema so you know what fields to pass:

```
get_cluster_workflow_schema
  cwf_name: dockerfile-builder
```

### 2. Create the Component with `workflow` set

```
create_component
  namespace_name: default
  project_name: default
  name: greeting-service
  component_type: deployment/service
  auto_deploy: true
  workflow:
    kind: ClusterWorkflow
    name: dockerfile-builder
    parameters:
      repository:
        url: https://github.com/openchoreo/sample-workloads
        revision:
          branch: main
        appPath: /service-go-greeter
      docker:
        context: /service-go-greeter
        filePath: /service-go-greeter/Dockerfile
```

**Do not call `create_workload`.** Source-build auto-generates `{component}-workload` from the build output (and from `workload.yaml` in the repo, if present).

### 3. (Recommended) Add `workload.yaml` to the repo

Put a `workload.yaml` at the root of `appPath` to declare endpoints, env vars, config files, and dependencies. Without it, the generated Workload only has `container.image` set — no endpoints, no env, nothing.

Copy `assets/workload-descriptor.yaml` into the repo at `<appPath>/workload.yaml` and edit. Schema fields:

- `endpoints[]` — `name`, `port`, `type` (HTTP/gRPC/etc), `visibility[]`, `basePath`, `schemaFile`
- `configurations.env[]` — literal `value` or `valueFrom.secretKeyRef`
- `configurations.files[]` — `mountPath` plus literal `value` or `valueFrom.path` (file in the repo) or `valueFrom.secretKeyRef`
- `dependencies.endpoints[]` — `component`, `name`, `visibility`, `envBindings`

Commit and push before triggering the build — the build reads the descriptor at build time.

### 4. Trigger a build

```
trigger_workflow_run
  namespace_name: default
  project_name: default
  component_name: greeting-service
  commit: <optional commit SHA — defaults to HEAD of the configured branch>
```

This uses the workflow already configured on the Component. For a one-off build with different parameters, `create_workflow_run` lets you supply a `parameters` object directly.

### 5. Monitor the build

```
list_workflow_runs
  namespace_name: default
  project_name: default
  component_name: greeting-service
```

Pick the latest run name from the list, then:

```
get_workflow_run
  namespace_name: default
  run_name: <run name>
```

Check `status.conditions` for `WorkflowSucceeded` / `WorkflowFailed`, and `status.tasks[]` for per-step phase (`Pending`, `Running`, `Succeeded`, `Failed`, `Skipped`, `Error`). Standard task names: `checkout-source`, `containerfile-build` (or builder-specific), `publish-image`, `generate-workload-cr`.

For build logs: tail `get_workflow_run_logs` while the run is in progress (optionally filter by `task`, optionally bound with `since_seconds`). Pair it with `get_workflow_run_events` if a task pod is stuck pending or failed to start. For *completed* failed runs, the live-log endpoint returns nothing — escalate to PE for `kubectl logs --previous` against the Argo pod, or rely on `get_workflow_run.status.conditions` and per-task phase to localize the failure.

### 6. Verify the deploy

After `WorkflowSucceeded`, the generated Workload triggers an auto-deploy (because `auto_deploy: true` on the Component). Verify with the same flow as BYOI:

```
get_component
list_release_bindings
get_release_binding
get_resource_events / get_resource_logs    # pod-level events and runtime logs once Ready
```

See `recipes/inspect-and-debug.md` for deeper inspection.

## Variant: auto-build on push

Add `autoBuild: true` to the Component. With both `autoBuild: true` and `autoDeploy: true`, every push to the configured branch (and within the configured `appPath`) builds and deploys automatically.

```yaml
spec:
  autoBuild: true
  autoDeploy: true
  workflow:
    parameters:
      repository:
        url: https://github.com/<org>/<repo>
        revision:
          branch: main
        appPath: /service
```

What triggers a build:
1. Push URL matches `repository.url`
2. Branch matches `repository.revision.branch`
3. The push includes a change inside `appPath`

If all three match, the platform creates a WorkflowRun automatically with the commit SHA.

> **PE setup required.** Auto-build needs a webhook receiver and webhook secret configured in the platform. If pushes don't trigger builds, escalate to `openchoreo-platform-engineer` to verify the webhook setup.

## Gotchas

- **Source-build vs BYOI is determined by `spec.workflow`.** Set it → source build (and the platform creates the Workload for you). Omit it → BYOI (you must create the Workload yourself).
- **For source-build, never call `create_workload` (MCP) or write a Workload CR.** The Workload is auto-generated as `{component}-workload` from the build output and the optional in-repo `workload.yaml`. Use `update_workload` only after a successful build, when the repo has no `workload.yaml` and you need to enrich the auto-generated minimal Workload.
- **`workload.yaml` must live at the root of `appPath`**, not at the repo root (unless `appPath` is `/`). Build-time read; commits after the build don't affect already-built releases.
- **Workflow must be in the ComponentType's `allowedWorkflows`.** If `create_component` fails with `ComponentValidationFailed`, the chosen workflow isn't allowed by the ComponentType — pick a different workflow or ask PE to extend `allowedWorkflows`.
- **WorkflowRuns are imperative, not declarative.** Each one starts a build. Do not commit WorkflowRun YAML to a GitOps repo — it'll trigger duplicate builds on every reconcile.
- **Required labels on a manual WorkflowRun YAML:** `openchoreo.dev/project` and `openchoreo.dev/component`. Missing them fails with `ComponentValidationFailed`. (Not an issue when using `trigger_workflow_run` — it sets the labels for you.)
- **Validation failures are permanent.** `ComponentValidationFailed` won't auto-retry — fix the spec and trigger a new run. `WorkflowPlaneNotFound` is transient and retried automatically.
- **Buildah builds fail on multi-platform Dockerfiles.** Third-party Dockerfiles using `ARG BUILDPLATFORM` typically exit 125 with a `BUILDPLATFORM` error. For third-party apps, prefer BYOI — see `recipes/deploy-prebuilt-image.md`.
- **Auto-build needs PE-side webhook setup.** Setting `autoBuild: true` alone isn't enough — pushes won't trigger builds without the webhook receiver. Escalate if it isn't working.
- **`trigger_workflow_run` vs `create_workflow_run`.** `trigger_workflow_run` starts a build using the component's configured workflow (optional `commit` SHA pins a revision). `create_workflow_run` creates a standalone run by workflow name with explicit parameters — use that for workflows that aren't tied to a component.
- **Workflow runs can lag.** A just-triggered run may briefly show no runs. Call `list_workflow_runs` after a moment, then verify with `get_component`.

## Related recipes

- [`deploy-prebuilt-image.md`](deploy-prebuilt-image.md) — BYOI: deploy an existing image instead of building
- [`configure-workload.md`](configure-workload.md) — env vars, files, endpoints in detail (mirrors the `workload.yaml` schema)
- [`connect-components.md`](connect-components.md) — declare dependencies on other components
- [`manage-secrets.md`](manage-secrets.md) — SecretReference patterns beyond Git auth
- [`inspect-and-debug.md`](inspect-and-debug.md) — runtime logs, status, debugging deployed components
- [`deploy-and-promote.md`](deploy-and-promote.md) — promote built releases across environments
