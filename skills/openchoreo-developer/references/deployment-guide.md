# Deploying Applications to OpenChoreo

## Quick navigation

Use this index to jump to the section you need — do not read the whole file.

| Task | Section |
|------|---------|
| Deploy a pre-built container image | [Pre-built Image (BYOI)](#pre-built-image-byoi---simplest-path) |
| Deploy from source / Git | [Building from Source](#building-from-source) |
| Understand how the CI build produces a Workload | [How the CI Pipeline Works](#how-the-ci-pipeline-works) |
| Write or fix `workload.yaml` (endpoints, dependencies) | [Workload Descriptor](#workload-descriptor-workloadyaml) |
| Author Component / Workload specs from the live cluster | [Using schema discovery](#using-schema-discovery) |
| Deploy to an environment or promote | [Deploying and Promoting](#deploying-and-promoting) |
| Override config per environment | [ReleaseBinding with Overrides](#releasebinding-with-overrides) |
| Multi-service app layout | [Multi-Service Applications](#multi-service-applications) |
| Env vars, secrets, file config | [Environment Variables and Configuration](#environment-variables-and-configuration) |
| Adapt a local app for OpenChoreo | [Making Local Apps Work on OpenChoreo](#making-local-apps-work-on-openchoreo) |
| Full deployment checklist | [End-to-End Deployment Checklist](#end-to-end-deployment-checklist) |
| Debug a stuck or failing deployment | [Debugging Deployments](#debugging-deployments) |

---

## Pre-built Image (BYOI) - Simplest Path

For apps with existing container images, you need Component + Workload resources. Both are created via MCP — see `recipes/deploy-prebuilt-image.md` for the canonical, parameter-by-parameter walkthrough. The shapes below show the underlying spec the MCP calls construct.

### Minimal example — Component spec (passed into `create_component`)

```yaml
autoDeploy: true
componentType:
  kind: ClusterComponentType    # or ComponentType for namespace-scoped
  name: deployment/service      # format: workloadType/typeName
owner:
  projectName: default
parameters: {}
```

### Minimal example — Workload spec (passed into `create_workload`)

```yaml
owner:
  componentName: my-app
  projectName: default
container:
  image: "myregistry/my-app:v1.0.0"
  env:
    - key: PORT
      value: "8080"
endpoints:
  http:
    port: 8080
    type: HTTP                  # HTTP | GraphQL | Websocket | gRPC | TCP | UDP
    visibility: ["external"]
```

### With Traits

Trait attachment requires editing `spec.traits[]` on the Component. **There is no MCP write surface for this** (`patch_component` does not cover it) — route to `openchoreo-platform-engineer` to apply a Component spec like:

```yaml
spec:
  autoDeploy: true
  componentType:
    name: deployment/service
  owner:
    projectName: default
  parameters: {}
  traits:
    - name: persistent-volume
      kind: ClusterTrait              # or Trait for namespace-scoped
      instanceName: data-storage
      parameters:
        volumeName: data
        mountPath: /var/data
        containerName: app
```

Per-environment trait *parameter overrides* are different — those use `update_release_binding` with `trait_environment_configs` and stay in this skill. See `recipes/override-per-environment.md`.

## Building from Source

For source-to-image builds, configure a Workflow on the Component. The exact workflow name and parameter schema come from the cluster — inspect with `list_cluster_workflows` and `get_cluster_workflow_schema`, or use a matching sample from `samples/from-source/`.

Component spec (passed into `create_component`):

```yaml
owner:
  projectName: default
componentType:
  kind: ClusterComponentType
  name: deployment/service
autoDeploy: true
workflow:
  kind: ClusterWorkflow
  name: dockerfile-builder
  parameters:
    repository:
      url: "https://github.com/myorg/my-app"
      revision:
        branch: "main"
      appPath: "."
    docker:
      context: "."
      filePath: "./Dockerfile"
```

Trigger builds: `trigger_workflow_run` for the component.
Follow build logs: `query_workflow_logs` with the run name.

**Important path rule for multi-directory repos**: `repository.appPath` tells the workflow where the service source lives and where to find `workload.yaml`, but Docker workflow paths still need to match the actual repo layout. If the service lives under `backend/` with `backend/Dockerfile`, use `docker.context: ./backend` and `docker.filePath: ./backend/Dockerfile` or the equivalent leading-slash form used by repo samples. Do not assume `appPath: ./backend` makes `./Dockerfile` resolve inside that directory.

**Important project rule for source builds**: The Component's `spec.owner.projectName` must match the project the workflow runs under. The workflow's parameter shape comes from the workflow's own schema — inspect with `get_cluster_workflow_schema` to confirm what the build pipeline accepts.

### The Workload is auto-generated — don't create one yourself

For source-build components, **never call `create_workload`**. The build's `generate-workload` step does it for you:

- It produces a Workload named **`{component}-workload`** (always — the descriptor's `metadata.name` is ignored).
- If `workload.yaml` exists at `appPath` root in the repo, the build inlines it: endpoints, dependencies, env vars, files all flow through.
- If `workload.yaml` is missing, the auto-generated Workload contains **only the container image** — no endpoints, no routing, no dependencies. The component will deploy but won't route any traffic.

After the build, query the workload by its real name:

```
list_workloads(namespace, project, component)        → see {component}-workload appear
get_workload(namespace, '{component}-workload')      → NOT '<component>' — that returns "not found"
```

### Enriching the auto-generated Workload

If you need to add endpoints, dependencies, or env vars after a build, there are two paths:

**Preferred — edit `workload.yaml` and rebuild.** Commit the descriptor changes, then `trigger_workflow_run`. The new build produces a fresh `{component}-workload` with the descriptor inlined. This is the canonical path: source of truth lives in the repo, deployments are reproducible, history is auditable.

**Fallback — `update_workload` against the auto-generated name.** Use this only when rebuilding isn't possible (e.g., the repo has no `workload.yaml` and you can't edit the source):

```
update_workload(namespace, workload_name='my-app-workload', workload_spec={...})
```

The spec body looks like:

```yaml
owner:
  projectName: my-project
  componentName: my-app
container:
  image: <existing image from the auto-generated workload>
endpoints:
  api:
    type: HTTP
    port: 8080
    visibility: ["external"]
# … endpoints, dependencies.endpoints[], etc.
```

> **`update_workload` sends the full spec, not a partial patch.** Always `get_workload` first, modify locally, send the complete `workload_spec` back. Omitting a field deletes it.

> **Don't omit `endpoints:`.** The default ComponentType (`deployment/service`) has a validation rule `${size(workload.endpoints) > 0}` — a Workload with no endpoints will cause `RenderingFailed` on the ReleaseBinding. If your component genuinely has no endpoints (a worker / job), use a worker / cronjob ComponentType instead.

> **Don't drop the image** when sending the updated spec. The auto-generated workload already has the built image set. If you send a Workload spec without the image (or with a wrong / placeholder image), you overwrite it. Read the current image first via `get_workload`.

## How the CI Pipeline Works

Understanding the build flow helps debug issues and explains why `workload.yaml` exists.

### The Problem workload.yaml Solves

A Dockerfile tells you how to build an image, but it doesn't tell the platform anything about your application's runtime needs: what ports it listens on, what protocol it speaks (REST vs gRPC), what other services it connects to, or what visibility its endpoints need. The platform needs this information to generate the right Kubernetes resources (Services, HTTPRoutes, network policies, env var injection for connections).

The `workload.yaml` descriptor bridges this gap. It's a declaration of your app's runtime contract that lives alongside your source code.

### Build Pipeline Flow

When you trigger a build (`trigger_workflow_run`), here's what happens:

```
1. Source checkout
   └── Clone repo, check out branch/commit

2. Build image
   └── Run Dockerfile (or buildpack), push image to registry

3. Generate Workload CR  (the key step)
   └── Read workload.yaml from your source (if present), merge with the built
       image reference and component/project context, emit a complete Workload CR.

4. Controller picks up the Workload CR
   └── Creates or updates the Workload resource in the control plane
   └── If autoDeploy is true, this triggers a new ComponentRelease and deployment
```

### The generate-workload-cr Step

The build workflow (an Argo Workflow) has a special step named `generate-workload-cr`. The WorkflowRun controller watches for this specific step name and reads its output parameter `workload-cr`.

This step reads your `workload.yaml`, merges it with the built image reference, and emits a full Workload CR. The controller then creates or updates the Workload in the control plane. (This is internal to the build pipeline — developers never invoke it directly.)

**With descriptor**: The Workload CR gets endpoints, dependencies, configurations, and the image. The platform knows how to route traffic, inject connection env vars, and configure networking.

**Without descriptor**: The Workload CR gets just the container image. No endpoints, no dependencies, no special configuration. The component deploys but the platform can't set up routing or service discovery for it.

### What This Means for You

- If your service exposes APIs or needs to talk to other services, you need a `workload.yaml`
- If it's a simple worker with no network exposure, you might skip it
- The descriptor must be at the `appPath` root so the build step can find it
- Build logs (`query_workflow_logs`) show whether the descriptor was found and processed
- After a successful build, check `get_workload` to verify endpoints and connections made it through

## Workload Descriptor (workload.yaml)

When building from source, place a `workload.yaml` at the root of the `appPath` directory. This tells the build workflow what endpoints, dependencies, and configurations your service has.

**Placement rules**:
- If `appPath: .` -> `workload.yaml` at repo root
- If `appPath: ./backend` -> `backend/workload.yaml`
- File must be named exactly `workload.yaml` (not `.workload.yaml`, not `Workload.yaml`)
- This is at the `appPath` root, not the docker context root

### Full Descriptor Schema

```yaml
apiVersion: openchoreo.dev/v1alpha1

metadata:
  name: my-service              # descriptive name for the workload

endpoints:
  - name: api                   # unique endpoint name
    port: 8080                  # exposed port (required)
    type: HTTP                  # HTTP | GraphQL | Websocket | gRPC | TCP | UDP
    targetPort: 8080            # container port (defaults to port)
    displayName: "REST API"     # human-readable name
    basePath: "/api/v1"         # URL path prefix
    schemaFile: openapi.yaml    # relative path to schema file (read and inlined)
    visibility:                 # additional scopes beyond implicit "project"
      - external

dependencies:
  endpoints:                    # nested under .endpoints
    - component: backend-api    # target component name (required)
      name: api                 # target endpoint name on the component (required)
      visibility: project       # project | namespace (required)
      project: other-project    # target project (optional, defaults to same project)
      envBindings:              # env vars injected with resolved addresses
        address: BACKEND_URL    # full connection string
        host: BACKEND_HOST      # hostname only
        port: BACKEND_PORT      # port number only
        basePath: BACKEND_PATH  # base path only

configurations:
  env:
    - name: LOG_LEVEL
      value: info               # literal value
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secrets      # SecretReference name
          key: password
  files:
    - name: config.json
      mountPath: /etc/config/config.json
      value: |                  # inline file content
        {"debug": false}
    - name: cert.pem
      mountPath: /etc/ssl/cert.pem
      valueFrom:
        secretKeyRef:
          name: tls-certs
          key: cert
```

### Endpoint Types
`HTTP`, `GraphQL`, `Websocket`, `gRPC`, `TCP`, `UDP` — exact casing matters, the API server is case-sensitive (e.g. `Websocket` not `WebSocket`, `gRPC` not `GRPC`).

### Visibility Values
- `project` - implicit for all endpoints, no extra gateway needed
- `namespace` - needs westbound gateway
- `internal` - needs westbound gateway
- `external` - needs northbound gateway (usually configured)

> The four levels above apply to *target endpoint* declarations. **Dependency entries (`dependencies.endpoints[*].visibility`) accept only `project` or `namespace`** — the API rejects `internal` / `external` there. Cross-namespace dependencies are not supported via this mechanism. See `recipes/connect-components.md`.

### Dependency EnvBindings
The platform resolves the target service address and injects env vars. Use dependencies instead of hardcoding URLs. At least one envBinding field should be set.

`address` format depends on the target endpoint's `type`:

- `HTTP` / `GraphQL`: `http://host:port/basePath`
- `Websocket`: `ws://host:port/basePath` *(in-cluster scheme; for browser-facing access use the `wss://` external URL from `get_release_binding` → `endpoints[*].externalURLs`, not the injected `address`)*
- `gRPC` / `TCP` / `UDP`: `host:port` (no scheme, no path)

If the target's `basePath` is empty, `address` ends at `host:port` with no trailing slash.

## Using schema discovery

Before authoring a Component or Workload spec, fetch the live schema from the cluster — that's the fastest way to construct a valid spec without guessing fields.

```
list_cluster_component_types               → what types exist
get_cluster_component_type_schema           → field shape for a chosen type
list_cluster_traits                         → what traits exist
get_cluster_trait_schema                    → trait parameter shape
get_workload_schema                         → Workload spec shape
list_cluster_workflows                      → build workflows
get_cluster_workflow_schema                 → workflow parameter shape
```

Pass `component_type: "{workloadType}/{name}"` (e.g. `deployment/service`) on `create_component` — that's the canonical format.

## Deploying and Promoting

`auto_deploy: true` on the Component creates the **first environment's** ReleaseBinding automatically. Subsequent environments are manual via `create_release_binding`. To roll back or replace the release on an existing binding, use `update_release_binding release_name: <new>`. To take a binding offline without deleting it, `update_release_binding_state release_state: Undeploy`.

The full step-by-step (first deploy, promotion, rollback, undeploy/redeploy) is in `recipes/deploy-and-promote.md`.

## ReleaseBinding with Overrides

For environment-specific configuration, create ReleaseBinding resources:

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ReleaseBinding
metadata:
  name: my-app-production
  namespace: default
spec:
  environment: production
  owner:
    componentName: my-app
    projectName: default
  componentTypeEnvironmentConfigs:
    replicas: 3
  traitEnvironmentConfigs:
    data-storage:             # keyed by trait instanceName
      size: 100Gi
      storageClass: production-ssd
  workloadOverrides:
    container:
      env:
        - key: LOG_LEVEL
          value: warn
```

## Multi-Service Applications

Each service becomes its own Component. For a typical frontend + backend app:

1. **Backend**: `deployment/service` ComponentType, workload descriptor with API endpoints
2. **Frontend**: `deployment/web-application` ComponentType (or similar available type)
3. **Communication**: Use dependencies in the frontend's workload descriptor to reference the backend
4. **Workflow choice**: If a frontend uses a custom Dockerfile, nginx proxy, or custom runtime, prefer the `docker` workflow over `react`

For source builds with separate directories:

```
my-app/
├── backend/
│   ├── Dockerfile
│   ├── workload.yaml          # backend descriptor at appPath root
│   └── src/
└── frontend/
    ├── Dockerfile
    ├── workload.yaml          # frontend descriptor at appPath root
    └── src/
```

Backend component uses `appPath: ./backend`, frontend uses `appPath: ./frontend`.

Frontend's workload.yaml uses dependencies:
```yaml
dependencies:
  endpoints:
    - component: backend-service
      name: api                       # target endpoint name
      visibility: project
      envBindings:
        host: BACKEND_HOST
        port: BACKEND_PORT
```

The platform injects the resolved backend host and port. This is safer for nginx-style reverse proxies because it avoids accidentally doubling a backend endpoint `basePath`.

## Environment Variables and Configuration

There are several ways to pass configuration to your app on OpenChoreo.

### Literal env vars in Workload

For non-sensitive config that's the same everywhere:
```yaml
# In Workload CR
container:
  env:
    - key: LOG_LEVEL
      value: info
    - key: APP_ENV
      value: production

# In workload.yaml descriptor
configurations:
  env:
    - name: LOG_LEVEL
      value: info
```

### Secrets via SecretReference

For sensitive values (API keys, database passwords, tokens). Never hardcode these.
```yaml
# 1. Create a SecretReference.
# The backing secret store must already be configured on the DataPlane by PE.
apiVersion: openchoreo.dev/v1alpha1
kind: SecretReference
metadata:
  name: my-secrets
  namespace: default
spec:
  template:
    type: Opaque
  data:
    - secretKey: db-password
      remoteRef:
        key: my-app/database
        property: password
  refreshInterval: 1h

# 2. Reference it in Workload
container:
  env:
    - key: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: my-secrets
          key: db-password

# Or in workload.yaml descriptor
configurations:
  env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: my-secrets
          key: db-password
```

If there's no ClusterSecretStore configured, this needs PE help to set up.

### Per-environment overrides via ReleaseBinding

For config that differs between dev/staging/prod (replicas, log levels, feature flags):
```yaml
# workloadOverrides inject extra env vars for a specific environment
workloadOverrides:
  container:
    env:
      - key: LOG_LEVEL
        value: debug        # debug in dev, warn in prod
      - key: FEATURE_FLAG_X
        value: "true"

# componentTypeEnvironmentConfigs for things in the ComponentType schema
componentTypeEnvironmentConfigs:
  replicas: 3
  cpuLimit: "1000m"
```

### Connection-injected env vars

When using Workload dependencies, the platform automatically injects env vars with resolved service addresses. You control the env var names through `envBindings`:
```yaml
dependencies:
  endpoints:
    - component: backend-api
      name: api               # target endpoint name on backend-api
      visibility: project
      envBindings:
        address: BACKEND_URL    # full connection string; may include endpoint basePath
        host: BACKEND_HOST      # e.g., backend-api
        port: BACKEND_PORT      # e.g., 8080
        basePath: BACKEND_PATH  # e.g., /api
```

Your app can read whichever form fits the integration point.

- For application code that wants the platform-resolved full upstream URL, `address` is convenient.
- For nginx or other reverse proxies that already own a path like `/api/`, prefer `host` and `port`, and handle `basePath` separately if needed. This avoids doubled paths such as `/api/api/...`.

**Important — TCP endpoints (databases, message brokers):** The `address` binding for a TCP endpoint injects a raw `host:port` string, NOT a protocol-specific DSN. Apps that expect a full connection string (e.g., `postgres://user:pass@host:5432/db?sslmode=disable`, `nats://host:4222`, `redis://host:6379`) will fail to parse the injected value. In these cases:
- Declare the dependency (for the cell diagram/topology) but **omit** `envBindings`, OR
- Set the full DSN as a literal env var using the resolved hostname from the release binding's `serviceURL.host` field
- Get the hostname from: `get_release_binding` → `endpoints[*].serviceURL.host`

```yaml
# Wrong — injects "host:port", not a postgres DSN
dependencies:
  endpoints:
    - component: my-postgres
      name: tcp
      visibility: project
      envBindings:
        address: DATABASE_URL   # ← will be "host:5432", breaks pgx/GORM

# Right — declare connection for topology, set DSN explicitly
dependencies:
  endpoints:
    - component: my-postgres
      name: tcp
      visibility: project       # no envBindings
container:
  env:
    - key: DATABASE_URL
      value: "postgres://user:pass@<serviceURL.host>:5432/db?sslmode=disable"
```

### File-based configuration

For config files (JSON, YAML, certificates):
```yaml
# In Workload CR
container:
  files:
    - key: config.json           # this becomes the filename
      mountPath: /etc/config     # this is the DIRECTORY — key is appended
      value: |
        {"cache_ttl": 300, "max_connections": 50}
  # Result: file is mounted at /etc/config/config.json

# In workload.yaml descriptor
configurations:
  files:
    - name: app-config
      mountPath: /etc/config
      value: |
        {"cache_ttl": 300, "max_connections": 50}
```

**Critical — `mountPath` is a directory, not a file path.** The controller appends the `key` to the `mountPath` to form the final path. If you set `mountPath: /etc/config/app.json` and `key: app.json`, the file lands at `/etc/config/app.json/app.json` (broken). Always set `mountPath` to the parent directory.

```yaml
# Wrong
- key: config.json
  mountPath: /usr/share/nginx/html/config.json  # ← file ends up at .../config.json/config.json

# Right
- key: config.json
  mountPath: /usr/share/nginx/html              # ← file ends up at .../html/config.json
```

**SPA runtime config pattern (React/Vue/Angular with nginx):** Frontends that fetch a `/config.json` at runtime to discover backend URLs need this file mounted with resolved external service URLs. Inject the file via the workload `files` mount, not build-time env vars.

```yaml
container:
  files:
    - key: config.json
      mountPath: /usr/share/nginx/html
      value: '{"apiUrl":"https://...","wsUrl":"wss://..."}'
```

**Always use `https://` and `wss://` for browser-facing URLs.** OpenChoreo serves frontends over HTTPS. If backend URLs in the injected config use `http://` or `ws://`, browsers will block requests due to mixed content policy — silently with no visible error. Get the correct external URLs from `get_release_binding` → `endpoints[*].externalURLs`, then use `https://` and `wss://` scheme.

## Making Local Apps Work on OpenChoreo

The main challenge when moving from local development to OpenChoreo is how services find each other. Locally you use `localhost:PORT` or docker-compose service names. On OpenChoreo, the platform manages service discovery through connections and env vars.

The goal is to make apps work in both environments without separate codebases.

### The Pattern: Env Vars with Local Defaults

The universal solution is: read service URLs from environment variables, with fallback defaults for local development.

**Node.js / Express:**
```javascript
// Before (hardcoded, breaks on OpenChoreo)
const backendUrl = "http://localhost:3001";

// After (works everywhere)
const backendUrl = process.env.BACKEND_URL || "http://localhost:3001";
```

**Python / Flask / FastAPI:**
```python
# Before
BACKEND_URL = "http://localhost:3001"

# After
BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:3001")
```

**Go:**
```go
// Before
backendURL := "http://localhost:3001"

// After
backendURL := os.Getenv("BACKEND_URL")
if backendURL == "" {
    backendURL = "http://localhost:3001"
}
```

On OpenChoreo, the `BACKEND_URL` env var is injected by the connection. Locally, the fallback kicks in.

### Frontend -> Backend Connectivity

Frontends are trickier because they run in the browser, not on the server. The browser can't read server-side env vars at runtime. Common patterns:

> **Read the frontend source before picking a pattern.** Look at `package.json`, `index.html`, and a couple of API call sites in `src/`:
>
> - **Single-page app (React / Vue / Angular bundle served by nginx, Static-site export):** the browser executes the JS and makes the API calls itself. Backend URLs **must be public addresses** — `https://...` and `wss://...`. Use the mounted runtime `config.json` approach (see "SPA runtime config pattern" earlier in this file under *File-based configuration*) so the same image works in dev and prod with different backend URLs. Don't inject in-cluster service addresses; the browser can't resolve them.
> - **Server-side rendered / templated app (Next.js SSR mode, Rails, Django, Express with server-rendered views):** the **server** makes the API calls. In-cluster addresses work fine, and an nginx reverse proxy (Pattern 2) is reasonable for path-based routing.
> - **Hybrid (Next.js with both SSR routes and client-side fetches):** the SSR server can use in-cluster addresses; the client-side fetches need public ones. Mount a runtime config and read it on both sides.
>
> Pick the wrong pattern and you'll either ship `http://service.cluster.local` to a browser (mixed-content blocked) or send public HTTPS traffic through your own pod for no reason.

**Pattern 1: Build-time env vars (React, Vue, Angular)**

Inject the API base path at build time. Prefer same-origin `/api` as the default; that works locally when you have a proxy and avoids shipping `http://localhost...` into an HTTPS deployment.

```javascript
// Vite / modern frontend (.env.local for local dev if needed)
// .env.local
VITE_API_URL=/api

// In code
const apiUrl = import.meta.env.VITE_API_URL ?? "/api";
```

If you use a framework that exposes env vars differently, apply the same rule: default to `/api`, and use `??` or an explicit undefined check when an empty string is a meaningful value.

On OpenChoreo, the frontend's `workload.yaml` can set this via configurations:
```yaml
configurations:
  env:
    - name: VITE_API_URL
      value: /api    # relative path, proxied by the platform
```

**Pattern 2: Nginx reverse proxy (recommended for production)**

The frontend serves static files and proxies API calls to the backend. This avoids CORS entirely.

```nginx
# nginx.conf
server {
    listen 8080;

    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        # Prefer host/port bindings so backend endpoint basePath does not get duplicated
        proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
        proxy_set_header Host $host;
    }
}
```

The frontend code always calls `/api/...` (relative path). Nginx proxies it to wherever the backend is.

On OpenChoreo, the connection injects `BACKEND_HOST` and `BACKEND_PORT`. Locally, you set the same env vars in docker-compose or your run script.

**Pattern 3: Same-origin deployment**

If both frontend and backend are on the same domain (which OpenChoreo can do via basePath routing), the frontend just uses relative URLs like `/api/users`. No configuration needed.

### What to Look For When Scanning a Project

When preparing a local app for OpenChoreo, scan for these patterns:

**Hardcoded localhost URLs**: `http://localhost:`, `http://127.0.0.1:`, `http://0.0.0.0:`
- Replace with env var reads with the localhost value as default

**Docker-compose service names**: `http://backend:3001`, `http://db:5432`
- Replace with env var reads. On OpenChoreo, connections provide the actual addresses

**Hardcoded ports**: The app must listen on the port it declares in its endpoint
- Make the listen port configurable via env var (e.g., `PORT`)

**Hardcoded database connection strings**: `postgres://user:pass@localhost:5432/db`
- Move to env var, use SecretReference on OpenChoreo for credentials

**CORS configuration**: If frontend and backend are separate origins locally
- On OpenChoreo with proper basePath routing or proxy, CORS may not be needed
- If it is needed, make allowed origins configurable via env var

**Relative vs absolute API paths in frontend code**: `fetch("http://localhost:3001/api/users")`
- Change to relative: `fetch("/api/users")`
- Set up nginx proxy or platform basePath routing

**Environment-specific config files**: `.env.production`, `config.prod.json`
- Move to workload.yaml configurations or ReleaseBinding workloadOverrides

### Adaptation Checklist

For each service in the project:

1. **Identify all outbound URLs** - grep for `http://`, `localhost`, service names from docker-compose
2. **Replace with env vars + defaults** - keeps local dev working while OpenChoreo can inject real values
3. **Make the listen port configurable** - `const port = process.env.PORT || 3001`
4. **Move secrets to env vars** - never bake credentials into images
5. **For frontends**: switch to relative API paths + proxy pattern, or use build-time env vars
6. **Create workload.yaml** - declare endpoints, dependencies with envBindings matching the env var names you chose
7. **Verify locally** - the app should still work with default env var values

After changes, tell the user exactly what was modified and why, so they understand the pattern for future services.

## Deploying Public Third-Party / Multi-Service Apps

When a user asks you to deploy a well-known open-source or publicly published multi-service app, follow this path rather than the general source-build path.

### Step 1 — Check whether pre-built images exist

Before touching Dockerfiles or build workflows, look for official published images:

- GitHub releases page or `release/` / `deploy/` directory in the repo
- Docker Hub, GitHub Container Registry (GHCR), cloud vendor registries
- README or CI workflows that reference image tags

If pre-built images exist, **always use the BYO image path**. Do not attempt a source build.

**Why source builds commonly fail for third-party repos:** Many projects use multi-platform Docker syntax (`ARG BUILDPLATFORM`, `FROM --platform=$BUILDPLATFORM`) for cross-architecture builds. OpenChoreo's buildah-based builder does not support this syntax and exits with code 125. If a source build fails with exit code 125 and the log mentions `BUILDPLATFORM` or `attempted to redefine "BUILDPLATFORM"`, switch to the pre-built image immediately.

### Step 2 — Read the official Kubernetes manifests for required env vars

The official Kubernetes manifests (or Helm values, docker-compose files) are the ground truth for what each service needs to start. Before writing any workload YAML, fetch them and extract:

- **Listen port** — many apps read `PORT` from the environment; the manifest shows the expected value
- **Feature flags** — vendor telemetry, profiling, tracing, and stats are often enabled by default but crash outside the target cloud environment; manifests show the disable flags
- **Service address env vars** — some services are wired by explicit env vars, not connection injection
- **Optional service addresses** — addresses for services that may not be deployed in your setup

**Do not assume dependencies alone are sufficient.** Dependencies inject service addresses, but they do not provide `PORT`, feature flags, or other app-level config.

### Step 3 — Create components without workflows

For BYO image deployments, call `create_component` **without** the `workflow` parameter. Adding a workflow forces a source build, clutters the UI with failed runs, and is entirely unnecessary when using pre-built images.

```
create_component(namespace, project, name, componentType)   ← no workflow param
```

### Step 4 — Create workloads with full env vars from the official manifests

Create each workload via `create_workload`. Each workload must include:

1. The pre-built image
2. **All env vars from the official manifest** — `PORT`, feature flags, and any explicit service addresses not covered by dependencies
3. Dependencies for service-to-service communication (using `envBindings`)

**`dependencies` is an object with an `endpoints` array** — each entry uses `name` for the target endpoint:

```yaml
dependencies:
  endpoints:
    - component: my-cache
      name: tcp                     # name of the target endpoint on my-cache
      visibility: project
      envBindings:
        address: CACHE_ADDR
```

### Common patterns when running cloud-native apps outside their native cloud

Many apps built for a specific cloud platform bundle vendor SDKs — profilers, distributed tracers, metric exporters, log forwarders — that are loaded eagerly at startup. Outside the target cloud, these SDKs may:

- Fail to load a required native binary (process crashes before serving any traffic)
- Hang waiting for a metadata endpoint that does not exist
- Emit noisy errors but continue running

**Detection:** A service with `status: Ready` that immediately crash-loops, logs a native module load error or SDK init failure before any application output, and never logs a "server listening on port X" message.

**Fix pattern:** Look for a disable flag in the official manifests or SDK documentation:

| Pattern | Common flag | Notes |
|---------|-------------|-------|
| Profiler SDK (any vendor) | `DISABLE_PROFILER=1` or `ENABLE_PROFILER=0` | Check per-service in official manifests |
| Distributed tracing SDK | `DISABLE_TRACING=1` or `OTEL_SDK_DISABLED=true` | Varies by SDK |
| Stats/metrics exporter | `DISABLE_STATS=1` | Check official manifests |
| Cloud metadata dependency | Set dummy endpoint env var | Some SDKs hit metadata server on startup |

**Always check the official manifests first** — they typically already set the correct disable flags for out-of-cloud deployment.

### Optional services and missing env vars

Apps may `panic` or crash at startup if an env var for an optional or add-on service is not set (e.g., an AI assistant service, a recommendation engine, a payments sandbox). If the env var is required by the app code but the service is not deployed:

- Set the env var to a placeholder address (e.g., `"optional-service:80"`)
- The app will start; calls to that service will fail at runtime, not at startup
- Log the placeholder so it is visible and can be replaced when the service is deployed

### Multi-service deployment approach

For apps with many services, create workloads in passes:

1. **Pass 1** — workloads with no dependencies. Call `create_workload` for each (simpler, fewer failure modes).
2. **Pass 2** — workloads that depend on Pass 1 services. Same call, with `dependencies.endpoints[]` populated.
3. Verify with `list_release_bindings` per component.
4. For any service still failing, immediately check `query_component_logs` — do not assume a platform issue before reading the app logs.

### Checklist for third-party app deployment

1. [ ] Find pre-built image registry (GitHub releases, Docker Hub, GHCR, cloud registry)
2. [ ] Fetch official Kubernetes/Helm manifests — extract env vars for every service
3. [ ] Identify services with cloud-vendor SDK dependencies — note disable flags
4. [ ] Identify optional service env vars — plan placeholder values
5. [ ] Create project (`create_project`)
6. [ ] Create all components via `create_component` **without** `workflow` parameter
7. [ ] Create workloads via `create_workload` with: image, all env vars from manifests, dependencies
8. [ ] Verify release binding status for each component (`list_release_bindings` / `get_release_binding`)
9. [ ] For any failing component, check logs with `query_component_logs` immediately before assuming platform issue

---

## End-to-End Deployment Checklist

1. **Verify MCP connectivity**: `list_namespaces`. If it fails, the control-plane MCP server isn't reachable — fix that before continuing.
2. **Pick the working scope**: confirm namespace and project exist (`list_projects`). Create a project with `create_project` if needed.
3. **Discover only what you need**:
   - Environments/pipeline: `list_environments`, `list_deployment_pipelines`
   - Component types: `list_cluster_component_types`, `get_cluster_component_type_schema`
   - Traits: `list_cluster_traits`, `get_cluster_trait_schema`
   - Workflows for source builds: `list_cluster_workflows`, `get_cluster_workflow_schema`
4. **Author the Component spec** from the schema. Set `spec.owner.projectName` and (for source builds) `spec.workflow.parameters.repository.*`.
5. **Configure source builds**: If building from source, set `spec.workflow` on the Component and add `workload.yaml` at the `appPath` root in the repo.
6. **Adapt the app**: Replace hardcoded URLs and secrets with env vars plus local defaults.
7. **Create the component**: `create_component`. For BYOI follow with `create_workload`. For source-build, the workload is auto-generated by the build — do not call `create_workload`.
8. **Build** (if from source): `trigger_workflow_run`, follow with `query_workflow_logs` and `get_workflow_run`.
9. **Verify**: `get_component`, `list_release_bindings`, `get_release_binding`, `query_component_logs`.
10. **Promote**: `create_release_binding` for each downstream environment, with optional `component_type_environment_configs` / `trait_environment_configs` / `workload_overrides`.

## Debugging Deployments

All debugging goes through MCP. Cluster-level access is out of scope for this skill — for that, hand off to `openchoreo-platform-engineer`.

```
# 1. Check component status and conditions
get_component(namespace, project, component)

# 2. Check workload
get_workload(namespace, '{component}-workload')

# 3. Check release bindings
list_release_bindings(namespace, project, component)
get_release_binding(namespace, binding_name)

# 4. View application logs
query_component_logs(namespace, project, component, environment, start_time, end_time)

# 5. View build logs
query_workflow_logs(namespace, workflow_run_name, start_time, end_time)

# 6. Check workflow runs
list_workflow_runs(namespace, project, component)
get_workflow_run(namespace, run_name)

# 7. Pod / Deployment events when component logs are empty (e.g. ImagePullBackOff)
get_resource_events(namespace, release_binding_name, group, version, kind, resource_name)

# 8. Pod logs for a specific crashing pod
get_resource_logs(namespace, release_binding_name, pod_name, since_seconds)
```

Treat workflow logs, Component status, and ReleaseBinding status as the source of truth. `list_workflow_runs` can lag briefly after a build that already completed successfully — confirm with `get_workflow_run` and `get_component`.

Read `status.conditions[]` on each resource. Common condition issues:

**ComponentType not found**: The referenced type doesn't exist. Check `list_cluster_component_types`.

**Build not running**: WorkflowPlane might not be configured. Escalate to PE.

**Rendering failed**: Usually a missing gateway or invalid parameter. Check the error message in conditions.

**Endpoint not accessible**: Verify the binding has a resolved URL via `get_release_binding` — inspect `status.endpoints[]`, `invokeURL`, `externalURLs`, and `internalURLs`. If no external URL is present, check endpoint visibility and gateway setup.

**Image pull errors**: Use `get_resource_events` on the Pod (the container logs are empty for `ImagePullBackOff`). Private registry needs imagePullSecrets in the ComponentType — escalate to PE.

**Workload not created by build**: Check that `workload.yaml` exists at the `appPath` root with the correct name. Check build logs (`query_workflow_logs`) for descriptor-related errors.

**Dockerfile not found during source build**: Verify `docker.context` and `docker.filePath` are repo-root-relative paths to the real Docker build inputs. `appPath` does not rewrite those paths.

**Workload exists but Component says it is missing**: Compare `get_workload` output against the Component's project. If `spec.owner.projectName` on the Workload is wrong, the source-build scope likely pointed at the wrong project. Fix the Component/workflow project refs, then regenerate the Workload; `spec.owner` is not safely patchable in place.

**Frontend loads but `/api/...` through the frontend returns 404**: Check whether the backend endpoint defines a `basePath` and the proxy upstream already includes it through a connection `address`. If so, switch the proxy to host/port bindings or remove the duplicated path.

**Frontend loads but browser requests fail with `localhost` or mixed-content behavior**: Check the built frontend env defaults. Prefer `/api` as the browser-facing default and avoid `||` fallbacks that can override intentional empty-string or same-origin configs.

If conditions show errors you can't resolve through MCP, escalate to `openchoreo-platform-engineer` with the exact error message.
