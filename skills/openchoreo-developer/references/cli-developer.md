# `occ` CLI — Developer Reference

Developer-specific `occ` commands and gotchas. For install, login, context, the full command table, and universal gotchas, see `openchoreo-core/references/cli.md`.

## Developer Commands

### `component scaffold`

Generates Component YAML from available ComponentTypes and Traits. Always prefer this over writing YAML from scratch.

```bash
# --type format is workloadType/typeName (e.g., deployment/service)
occ component scaffold my-app --clustercomponenttype deployment/service
occ component scaffold my-app --clustercomponenttype deployment/web-application --clustertraits storage,ingress
occ component scaffold my-app --clustercomponenttype deployment/web-application --clusterworkflow react
occ component scaffold my-app --clustercomponenttype deployment/web-application -o my-app.yaml
occ component scaffold my-app --clustercomponenttype deployment/web-application --skip-comments --skip-optional
```

### `component deploy`

```bash
occ component deploy my-app                                       # deploy latest release to root env
occ component deploy my-app --to staging                          # promote to staging
occ component deploy my-app --release my-app-20260126-143022-1    # deploy specific release
occ component deploy my-app --set spec.componentTypeEnvironmentConfigs.replicas=3
```

### `component logs`

```bash
occ component logs my-app                    # logs from lowest environment
occ component logs my-app --env production   # specific environment
occ component logs my-app --env dev -f       # follow logs
occ component logs my-app --since 30m        # last 30 minutes
occ component logs my-app --tail 100         # last 100 lines
```

### `component workflow` / `workflowrun`

```bash
occ component workflow run my-app             # trigger build
occ component workflow logs my-app -f         # follow build logs
occ component workflowrun list my-app         # list builds
occ workflow run migration --set spec.workflow.parameters.key=value
```

### `workload create`

```bash
occ workload create --name my-wl --component my-app --image nginx:latest
occ workload create --name my-wl --component my-app --descriptor workload.yaml
occ workload create --name my-wl --component my-app --descriptor workload.yaml --dry-run
```

### `componentrelease` / `releasebinding` (file-system mode only)

```bash
occ componentrelease generate --all
occ componentrelease generate --project my-proj --component my-comp
occ releasebinding generate --target-env development --use-pipeline default --all
```

## Developer Gotchas

**Docker workflow paths are repo-relative**: `repository.appPath` selects the source subdirectory and `workload.yaml`, but `docker.context` and `docker.filePath` must still point at real repo-root-relative paths. If `appPath` is `./backend`, a Dockerfile under `backend/` should use `docker.context: ./backend` and `docker.filePath: ./backend/Dockerfile`.

**Source-build project scope must match in three places**: Keep the active context project, `spec.owner.projectName`, and `spec.workflow.parameters.scope.projectName` aligned before the first build. A mismatched workflow scope can generate Workloads in the wrong project.

**`workflowrun list` can lag**: A just-finished build may still appear `Pending` briefly. Confirm completion with `occ component workflow logs`, `occ component get`, and `occ releasebinding get`.

**`workflow` subcommands are inconsistent about `--project`**:
- `occ component workflow run` accepts `--project`
- `occ component workflow logs` does not
- After changing projects, update or switch context before using `workflow logs`, `component get`, or similar follow-up commands.

**`releasebinding list` requires both `--project` and `--component`**:
- Wrong: `occ releasebinding list --project my-proj`
- Right: `occ releasebinding list --project my-proj --component my-app`

**Workload owners are not patch-friendly**: If a generated Workload has the wrong `spec.owner`, plan to regenerate or recreate it after fixing the Component/workflow project config rather than editing the owner in place.
