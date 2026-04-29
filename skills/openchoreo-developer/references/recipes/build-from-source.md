# Build from source

Build a container image from a Git repository using a CI workflow, then deploy it as a Component. The workflow clones the repo, runs the configured builder (Dockerfile / buildpacks / Ballerina), pushes the image, and auto-generates a Workload from the build output.

> **Tool surface preference: MCP first, `occ` CLI as fallback.** Same as every recipe in this skill.

## When to use

- The user wants OpenChoreo to build their image from source
- The repo has a Dockerfile, buildpack-compatible source, or Ballerina code
- For deploying an already-built image, see `recipes/deploy-prebuilt-image.md` instead

## Prerequisites

1. Logged in to the control plane:
   ```bash
   occ version
   occ config context list
   ```
2. A Project exists (see [Create a Project](deploy-prebuilt-image.md#variant-create-a-project)).
3. The repo URL, branch, and the path to the app inside the repo (`appPath`) are known.
4. The ClusterComponentType you'll use lists the workflow you want in `allowedWorkflows`. Discover what's available:
   - **MCP:** `mcp__openchoreo-cp__list_cluster_component_types`, then `mcp__openchoreo-cp__get_cluster_component_type` to read `allowedWorkflows`.
   - **CLI:** `occ clustercomponenttype get <name>`.

## Available builders

| ClusterWorkflow name | Builder | Builder-specific parameters |
|---|---|---|
| `dockerfile-builder` | Dockerfile / Containerfile | `docker.context`, `docker.filePath` |
| `gcp-buildpacks-builder` | Google Cloud buildpacks (Go, Java, Node, Python, .NET) | `buildEnv` (optional) |
| `paketo-buildpacks-builder` | Paketo buildpacks (Java, Node, Python, Go, .NET, Ruby, PHP) | `buildEnv` (optional) |
| `ballerina-buildpack-builder` | Ballerina | `buildEnv` (optional) |

All workflows share `repository.url`, `repository.revision.branch`, `repository.revision.commit` (optional), `repository.appPath`, and `repository.secretRef` (for private repos).

## Recipe — MCP (preferred)

### 1. Pick a workflow and inspect its schema

```
mcp__openchoreo-cp__list_cluster_workflows
```

Pick one, then read the parameter schema so you know what fields to pass:

```
mcp__openchoreo-cp__get_cluster_workflow_schema
  cwf_name: dockerfile-builder
```

### 2. Create the Component with `workflow` set

```
mcp__openchoreo-cp__create_component
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
mcp__openchoreo-cp__trigger_workflow_run
  namespace_name: default
  project_name: default
  component_name: greeting-service
  commit: <optional commit SHA — defaults to HEAD of the configured branch>
```

This uses the workflow already configured on the Component. For a one-off build with different parameters, `mcp__openchoreo-cp__create_workflow_run` lets you supply a `parameters` object directly.

### 5. Monitor the build

```
mcp__openchoreo-cp__list_workflow_runs
  namespace_name: default
  project_name: default
  component_name: greeting-service
```

Pick the latest run name from the list, then:

```
mcp__openchoreo-cp__get_workflow_run
  namespace_name: default
  run_name: <run name>
```

Check `status.conditions` for `WorkflowSucceeded` / `WorkflowFailed`, and `status.tasks[]` for per-step phase (`Pending`, `Running`, `Succeeded`, `Failed`, `Skipped`, `Error`). Standard task names: `checkout-source`, `containerfile-build` (or builder-specific), `publish-image`, `generate-workload-cr`.

For build logs:

```
mcp__openchoreo-obs__query_workflow_logs
  namespace: default
  workflow_run_name: <run name>
  task_name: <e.g. containerfile-build — omit to fetch all tasks>
  start_time: <RFC3339>
  end_time:   <RFC3339>
```

### 6. Verify the deploy

After `WorkflowSucceeded`, the generated Workload triggers an auto-deploy (because `auto_deploy: true` on the Component). Verify with the same flow as BYOI:

```
mcp__openchoreo-cp__get_component
mcp__openchoreo-cp__list_release_bindings
mcp__openchoreo-cp__get_release_binding
mcp__openchoreo-obs__query_component_logs    # runtime logs once Ready
```

See `recipes/inspect-and-debug.md` for deeper inspection.

## Recipe — `occ` CLI (fallback)

### 1. Author the Component YAML

Copy `assets/source-build-component.yaml`, edit `<COMPONENT_NAME>`, repo URL, branch, `appPath`, and the `docker.*` paths.

### 2. (Recommended) Add `workload.yaml` to the repo

Same as MCP step 3 — copy `assets/workload-descriptor.yaml`, edit, commit at `<appPath>/workload.yaml`.

### 3. Apply the Component

```bash
occ apply -f /tmp/component.yaml
```

### 4. Trigger a build

```bash
occ component workflow run greeting-service
```

### 5. Monitor

```bash
occ component workflowrun list greeting-service       # all runs for this component
occ workflowrun get <run-name>                        # full status, conditions, task phases
occ workflowrun logs <run-name>                       # stream all logs
occ workflowrun logs <run-name> -f                    # follow
occ component workflowrun logs greeting-service       # latest run for this component
```

### 6. Verify the deploy

```bash
occ component get greeting-service
occ releasebinding list --namespace default --project default --component greeting-service
occ component logs greeting-service
```

## Variant: private Git repository

The build needs Git credentials. The platform must have a ClusterSecretStore wired to a backend (Vault / AWS Secrets Manager / OpenBao) — that's a PE-side prerequisite. Once that's in place, the developer:

### 1. Create a SecretReference (CLI only — no MCP create)

There is no MCP tool to create a SecretReference. Copy `assets/secret-reference-git.yaml`, fill in `<SECRET_NAME>` and the secret backend path, then:

```bash
occ apply -f /tmp/secret-reference.yaml
```

Verify it exists:

```
mcp__openchoreo-cp__list_secret_references
  namespace_name: default
```

### 2. Reference it from the Component's workflow

Add `secretRef` under `repository`:

```yaml
workflow:
  parameters:
    repository:
      url: https://github.com/<org>/<private-repo>
      secretRef: <SECRET_NAME>
      revision:
        branch: main
      appPath: /
```

For SSH-based auth, use a Git URL with `git@github.com:...` and a SecretReference of type `kubernetes.io/ssh-auth` instead of `basic-auth`.

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
- **Required labels on a manual WorkflowRun YAML:** `openchoreo.dev/project` and `openchoreo.dev/component`. Missing them fails with `ComponentValidationFailed`. (Not an issue when using `trigger_workflow_run` MCP / `occ component workflow run` — those set the labels for you.)
- **Validation failures are permanent.** `ComponentValidationFailed` won't auto-retry — fix the spec and trigger a new run. `WorkflowPlaneNotFound` is transient and retried automatically.
- **No MCP for SecretReference create/update.** Read-only via `list_secret_references`. Use `occ apply -f` for create.
- **Buildah builds fail on multi-platform Dockerfiles.** Third-party Dockerfiles using `ARG BUILDPLATFORM` typically exit 125 with a `BUILDPLATFORM` error. For third-party apps, prefer BYOI — see `recipes/deploy-prebuilt-image.md`.
- **Auto-build needs PE-side webhook setup.** Setting `autoBuild: true` alone isn't enough — pushes won't trigger builds without the webhook receiver. Escalate if it isn't working.

## Related recipes

- [`deploy-prebuilt-image.md`](deploy-prebuilt-image.md) — BYOI: deploy an existing image instead of building
- [`configure-workload.md`](configure-workload.md) — env vars, files, endpoints in detail (mirrors the `workload.yaml` schema)
- [`connect-components.md`](connect-components.md) — declare dependencies on other components
- [`manage-secrets.md`](manage-secrets.md) — SecretReference patterns beyond Git auth
- [`inspect-and-debug.md`](inspect-and-debug.md) — runtime logs, status, debugging deployed components
- [`deploy-and-promote.md`](deploy-and-promote.md) — promote built releases across environments
