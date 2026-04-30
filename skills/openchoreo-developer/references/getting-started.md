# Getting started

**Load this when deploying an app or project to OpenChoreo for the first time** — no Project yet, or first time the user has touched this cluster. It walks you through the orientation (what's already provisioned, BYO vs source-build, which ComponentType, repo conventions, `autoDeploy` choice) and routes you into the right recipe for the actual create steps.

**Skip this when working with existing Components** — if you're changing an image, updating parameters, rebuilding from source, modifying a workload, promoting, or troubleshooting, go directly to the matching recipe in `./recipes/`. The recipes cover both first-time and ongoing flows; this file is the orientation that wraps the first deploy.

Pair this with `./concepts.md` (concepts always; getting-started only on a first-time deploy).

## 1. Pre-flight discovery — what does the namespace already provide?

OpenChoreo separates platform setup from app deployment. Before authoring any Component, confirm what the platform team has provisioned in the target namespace.

Run these MCP discovery calls:

- `list_namespaces` — pick the target. Default is `default` unless the team uses a dedicated namespace.
- `list_environments(namespace)` — at least one Environment must exist (typically `development`). If none, deployment is impossible until the platform team creates one.
- `list_deployment_pipelines(namespace)` — defines the promotion order across Environments. Without one, deploys still work for the first env but there's no promotion path.
- `list_cluster_component_types` **and** `list_component_types(namespace)` — the available application templates. The platform may register cluster-scoped (`ClusterComponentType`) or namespace-scoped (`ComponentType`) — check **both** lists; either is a valid pick. If both are empty, `create_component` will fail. See *Pick a ComponentType* below.
- `list_cluster_workflows` **and** `list_workflows(namespace)` — the available CI Workflows (`dockerfile-builder`, `gcp-buildpacks-builder`, `paketo-buildpacks-builder`, `ballerina-buildpack-builder` are typical cluster-scoped ones). Same dual-scope check applies. Relevant only for source-build.
- `list_cluster_traits` **and** `list_traits(namespace)` — the available cross-cutting capabilities (alerts, ingress, storage, OAuth2 proxy, etc.). Same dual-scope check. Skim before assuming a feature has to live in your app code.
- `list_dataplanes(namespace)` — at least one DataPlane must exist for any Environment to actually deploy. Read-only check.

If any required pre-req is missing, hand off per the SKILL.md's *What this skill cannot do* rule.

## 2. Pick a deployment shape

Two top-level paths:

### BYO image (prebuilt container image)

You provide an OCI image; OpenChoreo runs it. No build step.

- Resources you create: `Component` (no `spec.workflow`) **plus** `Workload`.
- Recipe: `./recipes/deploy-prebuilt-image.md`.
- Best for: third-party / public apps with published images, monorepos where CI lives elsewhere, ad-hoc images.

### Source-build (OpenChoreo builds from a Git repo)

You give OpenChoreo a Git repo + builder choice; the platform builds the image and auto-generates the Workload.

- Resources you create: `Component` with `spec.workflow` referencing a `ClusterWorkflow`. The build creates `{component}-workload`; do **not** call `create_workload`.
- Recipe: `./recipes/build-from-source.md`.
- Best for: first-party code where you want OpenChoreo's build pipeline to manage image lifecycle.

> **Third-party / public apps: default to BYO.** Source builds commonly fail on third-party Dockerfiles because they use `ARG BUILDPLATFORM` multi-stage syntax that OpenChoreo's buildah builder does not support. If you see exit code 125 with a `BUILDPLATFORM` error, switch to BYO immediately.

## 3. Pick a ComponentType

The `componentType` reference (format: `{workloadType}/{name}`) determines what Kubernetes resources the platform generates. Common shapes the default platform setup ships:

| ComponentType | Use for |
|---|---|
| `deployment/service` | Backend HTTP / gRPC / TCP services |
| `deployment/web-application` | Public-facing frontends (SPAs, server-rendered web apps) |
| `deployment/worker` | Background workers, queue consumers, load generators |
| `statefulset/datastore` | Stateful stores (databases, message brokers) |
| `cronjob/*` | Scheduled jobs |
| `job/*` | One-shot batch jobs |

If the namespace has its own namespace-scoped ComponentTypes, `list_component_types` shows them. Always confirm the available list with `list_cluster_component_types` (and `list_component_types`) before assuming a name exists.

For each candidate, fetch the schema (`get_cluster_component_type_schema <name>`) before authoring — it tells you which `parameters` the type accepts and what their constraints are.

## 4. Repo conventions for source-build

If you chose source-build, the build flow is:

```
Git repo → ClusterWorkflow (build steps) → image push → workload.yaml (optional) → {component}-workload CR
```

What lives where:

- **`Dockerfile`** — at the path your `dockerfile-builder` workflow expects (usually repo root; override via `docker.context` / `docker.filePath`). Both fields are **repo-root-relative even when `appPath` is set**.
- **`workload.yaml`** (optional) — a workload descriptor at the root of the selected `appPath`. The build merges it into the auto-generated `{component}-workload` CR.
- **Without `workload.yaml`** the build creates a minimal Workload with just the image — no endpoints, no env vars, no dependencies. You'll usually want a `workload.yaml` so the cell diagram is complete and dependencies can resolve.

The `workload.yaml` descriptor uses a slightly different shape than the Workload CR. The build's `generate-workload-cr` step transforms one into the other:

| Field | Workload CR | `workload.yaml` descriptor |
|---|---|---|
| Env vars | `container.env[].key` | `configurations.env[].name` |
| File mounts | `container.files[].key` | `configurations.files[].name` |
| Endpoints | `endpoints` (map keyed by name) | `endpoints[]` (list with `name`) |

> **The auto-generated workload is always `{component}-workload`** — even if `workload.yaml` declares a different `metadata.name`, the build overrides it. So `get_workload my-svc` returns nothing; use `get_workload my-svc-workload`.

## 5. `autoDeploy` decision

`Component.spec.autoDeploy` controls what happens after a new `ComponentRelease` is created (on Component creation, Workload update, or successful build):

- **`autoDeploy: true`** (default if omitted) — OpenChoreo auto-creates a `ReleaseBinding` for the *first* environment in the DeploymentPipeline. Promotion to subsequent environments still requires explicit action.
- **`autoDeploy: false`** — nothing deploys until you explicitly call `create_release_binding`.

Pick `true` for active development (every push lands in dev). Pick `false` if a human gate is required even for the first environment.

## 6. Where to go next

Once you've decided BYO vs source-build and picked a ComponentType, route to the matching recipe:

- BYO image: `./recipes/deploy-prebuilt-image.md`
- Source-build: `./recipes/build-from-source.md`
- Multi-component apps with dependencies: also load `./recipes/connect-components.md`
- Secrets / env vars / files / per-env overrides: `./recipes/manage-secrets.md`, `./recipes/configure-workload.md`, `./recipes/override-per-environment.md`
- After deployment: `./recipes/deploy-and-promote.md` (promote across envs), `./recipes/inspect-and-debug.md` (verify / troubleshoot)
