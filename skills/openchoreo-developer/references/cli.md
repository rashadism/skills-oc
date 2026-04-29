# `occ` CLI

Single source of truth for the `occ` CLI: install, login, the full command surface, workflow commands (scaffold, deploy, build, logs), and every gotcha. Used by `openchoreo-developer`, `openchoreo-install`, and `openchoreo-platform-engineer` as their CLI reference — no per-skill duplicates.

> **Reach for `occ` when MCP doesn't cover the operation, or for inherently CLI-only flows: `login`, `version`, `config context`, `apply -f`, `component scaffold`, single-resource `get` for inspection.** For resource CRUD, schema discovery, and observability queries (logs, metrics, traces, alerts) prefer MCP — see `mcp.md`. Full preference logic and the per-operation override is in `SKILL.md` → "Tool preference order".

For platform-resource creation patterns specifically (Environment, DeploymentPipeline, Project YAML applied via `occ apply -f`), the YAML shapes live in `resource-schemas.md` and detailed authoring sits in the workflow skills (`openchoreo-platform-engineer/references/component-types-and-traits.md`, `workflows.md`, `authz.md`).

## Install

> **Official docs**: https://openchoreo.dev/docs/user-guide/cli-installation/

```bash
# macOS Apple Silicon (ARM64)
curl -L https://github.com/openchoreo/openchoreo/releases/download/v1.0.0/occ_v1.0.0_darwin_arm64.tar.gz \
  | tar -xz && sudo mv occ /usr/local/bin/

# macOS Intel (AMD64)
curl -L https://github.com/openchoreo/openchoreo/releases/download/v1.0.0/occ_v1.0.0_darwin_amd64.tar.gz \
  | tar -xz && sudo mv occ /usr/local/bin/

# Linux x64
curl -L https://github.com/openchoreo/openchoreo/releases/download/v1.0.0/occ_v1.0.0_linux_amd64.tar.gz \
  | tar -xz && sudo mv occ /usr/local/bin/

# Linux ARM64
curl -L https://github.com/openchoreo/openchoreo/releases/download/v1.0.0/occ_v1.0.0_linux_arm64.tar.gz \
  | tar -xz && sudo mv occ /usr/local/bin/
```

Check the latest release: https://github.com/openchoreo/openchoreo/releases/latest

Verify: `occ version`

## Setup Flow

After installing, the CLI needs to know where the OpenChoreo API server is. Ask the user for this URL if you don't know it. Never assume localhost.

```bash
# 1. Configure control plane endpoint
occ config controlplane update default --url <API_SERVER_URL>

# 2. Login (opens browser for PKCE auth)
occ login

# 3. Verify connection
occ namespace list

# 4. Create a context with defaults (optional but recommended)
occ config context add myctx --controlplane default --credentials default \
  --namespace default --project my-project

# 5. Use the context
occ config context use myctx

# 6. Inspect — list every context, current one marked with *
occ config context list
```

> **There is no `occ context` command.** Context management lives under `occ config context`. The full subcommand set is `add | list | use | update | delete` — no `current` / `show` / `get`. To see which context is active, use `occ config context list` and look for the `*` marker.

For local installs, ensure `/etc/hosts` has entries for `api.openchoreo.localhost`, `thunder.openchoreo.localhost`, and `observer.openchoreo.localhost` pointing to `127.0.0.1`.

### Service-account login

```bash
occ login --client-credentials --client-id <id> --client-secret <secret>
```

> **Gotcha — `service_mcp_client` does not work here.** The service account used to mint MCP tokens cannot be used with `occ login --client-credentials` (`unauthorized_client`). Use browser-based `occ login`, or a service account specifically configured for the occ OIDC flow.

## Config Modes

- **api-server** (default): Talks to the remote OpenChoreo API server.
- **file-system**: Works with local YAML files for GitOps workflows.

## Global Flags

Common short flags across `occ` subcommands (v1.0.0-rc.2+):
- `-n` — namespace
- `-p` — project
- `-c` — component

Flag support is **not uniform** across `occ` subcommands:

- Many `list` commands accept scope flags such as `--project` / `-p`.
- Many `get` commands use `--namespace` / `-n` only and do not accept `--project`.
- Some workflow subcommands (e.g. `occ component workflow logs`) accept `--namespace` but not `--project`.

Use `--help` on the exact subcommand when scope handling matters. Context defaults often carry project selection more reliably than flags.

## `occ get` returns YAML

Unlike kubectl, `occ` has no `--output` / `-o` flag. `occ <resource> get <name>` always returns the full YAML — spec + status. This is the primary way to inspect and debug resources.

```bash
occ component get my-app             # spec, type ref, status conditions
occ workload get my-workload         # container image, ports, dependencies
occ environment get dev              # dataplane mapping, status
occ componenttype get web-app        # schema, templates, allowed workflows
occ trait get ingress                 # trait schema, creates, patches
occ releasebinding get my-binding    # env overrides, deployment status
occ deploymentpipeline get default   # environment progression paths
```

Look at `status.conditions` in the output. Each condition has `type`, `status`, `reason`, and `message` fields that explain what's happening.

## Commands Quick Reference

| Command | Aliases | Actions |
|---|---|---|
| `namespace` | `ns` | list, get, delete |
| `project` | `proj` | list, get, delete |
| `component` | `comp` | list, get, delete, scaffold, deploy, logs, workflow run/logs, workflowrun list/logs |
| `environment` | `env` | list, get, delete |
| `dataplane` | `dp` | list, get, delete |
| `workflowplane` | `wp` | list, get, delete |
| `observabilityplane` | `op` | list, get, delete |
| `deploymentpipeline` | `deppipe` | list, get, delete |
| `componenttype` | `ct` | list, get, delete |
| `clustercomponenttype` | `cct` | list, get, delete |
| `trait` | `traits` | list, get, delete |
| `clustertrait` | `clustertraits` | list, get, delete |
| `workflow` | `wf` | list, get, delete, run, logs |
| `clusterworkflow` | `cwf` | apply, list, get, delete, run, logs |
| `workflowrun` | `wr` | list, get, logs |
| `secretreference` | `sr` | list, get, delete |
| `workload` | `wl` | create, list, get, delete |
| `componentrelease` | — | generate (fs-mode), list, get |
| `releasebinding` | — | generate (fs-mode), list, get, delete |
| `clusterauthzrole` | `car` | list, get, delete |
| `clusterauthzrolebinding` | `carb` | list, get, delete |
| `authzrole` | — | list, get, delete |
| `authzrolebinding` | `rb` | list, get, delete |

## Universal commands

### apply

```bash
occ apply -f <file.yaml>    # Create/update resources from YAML
occ apply -f <directory>    # Apply every .yaml/.yml file in the directory
occ apply -f https://...    # Apply from a URL
```

> **Gotcha — stdin doesn't work.** `occ apply -f -` fails with `path - does not exist`. Unlike kubectl, `occ` does not accept piped YAML. Always write YAML to a temp file first:
>
> ```bash
> # Wrong — fails with: path - does not exist
> cat <<EOF | occ apply -f -
> apiVersion: openchoreo.dev/v1alpha1
> kind: Environment
> ...
> EOF
>
> # Right — write to temp file, then apply
> cat > /tmp/env.yaml <<'EOF'
> apiVersion: openchoreo.dev/v1alpha1
> kind: Environment
> ...
> EOF
> occ apply -f /tmp/env.yaml
> ```

### get / list

```bash
occ <resource> get <name>           # full YAML, spec + status
occ <resource> list                  # summary list
occ <resource> list --project <p>    # most list commands accept --project
```

## Component Lifecycle Commands

### `component scaffold`

Generates Component YAML from available ComponentTypes and Traits. Always prefer this over writing YAML from scratch.

```bash
# Cluster-scoped (most common — default platform setup)
occ component scaffold my-app --clustercomponenttype deployment/service

# With cluster-scoped traits and workflow
occ component scaffold my-app --clustercomponenttype deployment/web-application \
  --clustertraits storage,ingress --clusterworkflow dockerfile-builder

# Output to file
occ component scaffold my-app --clustercomponenttype deployment/web-application -o my-app.yaml

# Minimal output for templating
occ component scaffold my-app --clustercomponenttype deployment/web-application --skip-comments --skip-optional

# Namespace-scoped (when the org provides custom namespace-scoped types)
occ component scaffold my-app --componenttype deployment/service
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

## Exploration Workflow

When working with an unfamiliar OpenChoreo cluster, explore in this order:

```bash
occ namespace list                   # what namespaces exist?
occ config context update myctx --namespace <ns>

occ project list                     # what projects exist?
occ environment list                 # what environments are available?
occ deploymentpipeline list          # what promotion paths exist?

occ clustercomponenttype list        # what component types are available cluster-wide?
occ componenttype list               # what types are available in this namespace?
occ clustertrait list                # what traits are available cluster-wide?
occ trait list                       # what traits are in this namespace?
occ clusterworkflow list             # what build workflows exist cluster-wide?
occ workflow list                    # what build workflows exist in this namespace?

occ component list --project my-proj # what components are deployed?
occ workload list                    # what workloads exist?
```

## Gotchas

**No `--output` / `-o` flag**: Unlike kubectl, `occ get` always returns YAML. There is no JSON or table output option.

**`list` vs `get` scope**: `list` commands respect `--project`. `get` commands work with `--namespace` only — scoping for `get` flows through context defaults.

**`scaffold` flag pairs are scope-specific**: The single `--type` flag was removed in v1.0.0-rc.2. Use the namespace-scoped flags (`--componenttype`, `--traits`, `--workflow`) **or** the cluster-scoped flags (`--clustercomponenttype`, `--clustertraits`, `--clusterworkflow`) — they are mutually exclusive. Cluster-scoped types are the platform default, so most scaffolds use the cluster flags.

**Type format is `workloadType/typeName`**: e.g., `deployment/service`, not just `service`.

**`scaffold` component name is positional**: There is no `--name` flag — the component name is the first positional argument.

**`component get` has no `--project` flag**: Use `--namespace` and rely on context defaults for project scope.

**`deploymentPipelineRef` is now an object**: In Project YAML, use `{kind: DeploymentPipeline, name: default}`, not the plain string form (changed in v1.0.0). `kind` is optional and defaults to `DeploymentPipeline`.

**`occ apply -f -` (stdin) does not work** — see the `apply` section above. Pipe-into-occ patterns must be replaced with temp-file patterns.

**`service_mcp_client` cannot be used for `occ login --client-credentials`** — see Setup Flow above.

**There is no `occ context` top-level command.** Use `occ config context <subcommand>`. To inspect the currently active context, use `occ config context list` (active one is marked `*`) — there is no `current` / `show` / `get` subcommand. See Setup Flow above.

**Docker workflow paths are repo-relative**: `repository.appPath` selects the source subdirectory and `workload.yaml`, but `docker.context` and `docker.filePath` must still point at real repo-root-relative paths. If `appPath` is `./backend`, a Dockerfile under `backend/` should use `docker.context: ./backend` and `docker.filePath: ./backend/Dockerfile`.

**`workflowrun list` can lag**: A just-finished build may still appear `Pending` briefly. Confirm completion with `occ component workflow logs`, `occ component get`, and `occ releasebinding get`.

**`workflow` subcommands are inconsistent about `--project`**:
- `occ component workflow run` accepts `--project`
- `occ component workflow logs` does not
- After changing projects, update or switch context before using `workflow logs`, `component get`, or similar follow-up commands.

**`releasebinding list` requires both `--project` and `--component`**:
- Wrong: `occ releasebinding list --project my-proj`
- Right: `occ releasebinding list --project my-proj --component my-app`

**Workload owners are not patch-friendly**: If a generated Workload has the wrong `spec.owner`, plan to regenerate or recreate it after fixing the Component/workflow project config rather than editing the owner in place.

**DeploymentPipeline applied with `occ apply` works in v1.0.0+**: Earlier versions had a client/server schema disagreement on `sourceEnvironmentRef`. As of v1.0.0 the `occ apply` registry handles `DeploymentPipeline` correctly — provided the YAML uses the canonical object form (`{name: <env>}`), which has always been the API server's expected shape.
