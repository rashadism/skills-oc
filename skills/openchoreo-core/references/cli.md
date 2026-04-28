# `occ` CLI — Foundational Reference

The `occ` CLI manages OpenChoreo resources. This file covers install, login, context, the command surface, and gotchas that apply to every workflow.

For workflow-specific command details:
- Application work — `openchoreo-developer/references/cli-developer.md`
- Platform engineering (ComponentTypes, Traits, Workflows, Authz) — see the `openchoreo-platform-engineer` skill's reference routing
- Cluster install — `openchoreo-install/references/`

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

> **Note**: `~/.choreo/bin/choreo` is the WSO2 commercial Choreo cloud CLI — a different product that cannot manage OpenChoreo resources.

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
```

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

## Universal Gotchas

**No `--output` / `-o` flag**: Unlike kubectl, `occ get` always returns YAML. There is no JSON or table output option.

**`list` vs `get` scope**: `list` commands respect `--project`. `get` commands work with `--namespace` only — scoping for `get` flows through context defaults.

**`scaffold` flag pairs are scope-specific**: The single `--type` flag was removed in v1.0.0-rc.2. Use the namespace-scoped flags (`--componenttype`, `--traits`, `--workflow`) **or** the cluster-scoped flags (`--clustercomponenttype`, `--clustertraits`, `--clusterworkflow`) — they are mutually exclusive. Cluster-scoped types are the platform default, so most scaffolds use the cluster flags.

```bash
# Cluster-scoped (most common — default platform setup)
occ component scaffold my-app --clustercomponenttype deployment/service

# With cluster-scoped traits and workflow
occ component scaffold my-app --clustercomponenttype deployment/web-application \
  --clustertraits storage,ingress --clusterworkflow dockerfile-builder

# Namespace-scoped (when the org provides custom namespace-scoped types)
occ component scaffold my-app --componenttype deployment/service
```

**Type format is `workloadType/typeName`**: e.g., `deployment/service`, not just `service`.

**`scaffold` component name is positional**: There is no `--name` flag — the component name is the first positional argument.

**`component get` has no `--project` flag**: Use `--namespace` and rely on context defaults for project scope.

**`deploymentPipelineRef` is now an object**: In Project YAML, use `{kind: DeploymentPipeline, name: default}`, not the plain string form (changed in v1.0.0).

**`occ apply -f -` (stdin) does not work** — see the `apply` section above. Pipe-into-occ patterns must be replaced with temp-file patterns.

**`service_mcp_client` cannot be used for `occ login --client-credentials`** — see Setup Flow above.
