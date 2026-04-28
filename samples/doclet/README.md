# Sample: Deploy Doclet (Collaborative Document Editor) on OpenChoreo

This sample shows how to deploy [Doclet](https://github.com/lakwarus/doclet) — a real-time collaborative document editor with a Go backend, NATS message broker, PostgreSQL database, and React frontend — onto OpenChoreo using Claude Code with the `openchoreo-developer` skill and the `openchoreo-cp` MCP server.

---

## What this sample covers

- Mixed deployment: BYO images (PostgreSQL, NATS) + source builds (Go services, React SPA)
- TCP service connections where **envBindings must NOT be used** — injected value is `host:port`, not a DSN
- Setting explicit DSN env vars using `serviceURL.host` from `get_release_binding`
- Runtime config pattern for SPAs: mounting `config.json` at a directory path (not a file path)
- Mixed content pitfall: frontend served over HTTPS must use `https://` and `wss://` backend URLs
- Calling `update_workload` after source builds that have no `workload.yaml` in the repo
- Correct `update_workload` parameter signature (no `project_name` or `component_name`)
- Correct WebSocket endpoint type value: `"Websocket"` (lowercase s)

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Claude Code with skills loaded | `openchoreo-developer` from this repo |
| `openchoreo-cp` MCP server registered | See [MCP configuration guide](https://openchoreo.dev/docs/reference/mcp-servers/mcp-ai-configuration/) |
| OpenChoreo cluster | With a DataPlane, `development` environment, `deployment/service`, `deployment/web-application` ComponentTypes, and `dockerfile-builder` ClusterWorkflow |

---

## The prompt

```
Deploy the repository https://github.com/lakwarus/doclet into OpenChoreo.
Create a new project called "doclet" and deploy the workload in the development environment.
```

That is the entire prompt. Claude will:

1. Activate the `openchoreo-developer` skill
2. Fetch the repo to understand services, Dockerfiles, ports, and env vars
3. Discover available ComponentTypes and Workflows from the live cluster
4. Create the project and all 5 components
5. Apply BYO workloads for PostgreSQL and NATS
6. Trigger source builds for the three application services (in parallel)
7. After builds complete: wire up workloads with endpoints, env vars, and dependencies
8. Mount a runtime `config.json` into the frontend with resolved `https://` URLs

---

## Application architecture

| Component | ComponentType | Build | Description |
|---|---|---|---|
| `doclet-postgres` | `deployment/service` | BYO (`postgres:16-alpine`) | PostgreSQL 16 database |
| `doclet-nats` | `deployment/service` | BYO (`nats:2.10-alpine`) | NATS 2.10 message broker |
| `document-svc` | `deployment/service` | Source — `dockerfile-builder` | REST API backend (Go, `:8080`) |
| `collab-svc` | `deployment/service` | Source — `dockerfile-builder` | WebSocket collaboration service (Go, `:8090`) |
| `doclet-frontend` | `deployment/web-application` | Source — `dockerfile-builder` | React SPA served by nginx (`:80`) |

Source build config (per service):

| Component | `dockerfilePath` | `dockerContext` |
|---|---|---|
| `document-svc` | `./services/document/Dockerfile` | `.` |
| `collab-svc` | `./services/collab/Dockerfile` | `.` |
| `doclet-frontend` | `./frontend/Dockerfile` | `.` |

---

## Timing

| Phase | Duration |
|---|---|
| Repo inspection + cluster discovery | ~1 min |
| Project + 5 component creation | ~1 min |
| BYO workloads applied + Ready | ~1 min |
| Source builds (all 3 in parallel) | ~4 min |
| Workload wiring (update × 3) | ~1 min |
| Frontend Ready (with config.json) | ~2 min |
| **Total end-to-end** | **~10 min** |

## What Claude does (step by step)

### Phase 1 — Repo inspection
- Fetches the GitHub repo to identify services, Dockerfiles, ports, and env vars
- Identifies: 2 BYO infrastructure components + 3 source-build application components
- Notes: no `workload.yaml` in the repo → `update_workload` will be needed after each build

### Phase 2 — Cluster discovery
- `list_cluster_component_types` → confirms `deployment/service`, `deployment/web-application`
- `list_cluster_workflows` → confirms `dockerfile-builder` is available
- `list_environments` → confirms `development` environment exists

### Phase 3 — Create components
```
create_project(default, doclet)
create_component(doclet-postgres, deployment/service)           # no workflow
create_component(doclet-nats,     deployment/service)           # no workflow
create_component(document-svc,    deployment/service, dockerfile-builder)
create_component(collab-svc,      deployment/service, dockerfile-builder)
create_component(doclet-frontend, deployment/web-application, dockerfile-builder)
```

### Phase 4 — Apply BYO workloads
```
create_workload(doclet-postgres) → postgres:16-alpine, TCP:5432, visibility: project
create_workload(doclet-nats)     → nats:2.10-alpine,  TCP:4222, visibility: project
```

### Phase 5 — Trigger source builds (parallel)
```
trigger_workflow_run(document-svc,    commit: HEAD)
trigger_workflow_run(collab-svc,      commit: HEAD)
trigger_workflow_run(doclet-frontend, commit: HEAD)
```
Wait ~4 minutes. Verify with `list_workflow_runs`.

### Phase 6 — Get infrastructure hostnames
```
get_release_binding(doclet-postgres-development) → endpoints[0].serviceURL.host
get_release_binding(doclet-nats-development)     → endpoints[0].serviceURL.host
```

### Phase 7 — Wire up service workloads
```
get_workload(document-svc-workload) → current image
update_workload(document-svc-workload, spec below)

get_workload(collab-svc-workload)   → current image
update_workload(collab-svc-workload, spec below)
```

### Phase 8 — Get external URLs and wire frontend
```
get_release_binding(document-svc-development) → externalURLs.http → https://...
get_release_binding(collab-svc-development)   → externalURLs.http → wss://...

get_workload(doclet-frontend-workload) → current image
update_workload(doclet-frontend-workload, spec below)
```

---

## Complete workload specs

### doclet-postgres (BYO)

```json
{
  "container": {
    "image": "postgres:16-alpine",
    "env": [
      {"key": "POSTGRES_USER",     "value": "doclet"},
      {"key": "POSTGRES_PASSWORD", "value": "doclet"},
      {"key": "POSTGRES_DB",       "value": "doclet"}
    ]
  },
  "endpoints": {
    "tcp": {"port": 5432, "type": "TCP", "visibility": ["project"]}
  }
}
```

### doclet-nats (BYO)

```json
{
  "container": {"image": "nats:2.10-alpine"},
  "endpoints": {
    "tcp": {"port": 4222, "type": "TCP", "visibility": ["project"]}
  }
}
```

### document-svc (after source build)

> Replace `<postgres-host>` and `<nats-host>` with `serviceURL.host` from the release bindings.

```json
{
  "container": {
    "image": "<built-image-from-ecr>",
    "env": [
      {"key": "DOCLET_DOCUMENT_ADDR", "value": ":8080"},
      {"key": "DOCLET_DATABASE_URL",  "value": "postgres://doclet:doclet@<postgres-host>:5432/doclet?sslmode=disable"},
      {"key": "DOCLET_NATS_URL",      "value": "nats://<nats-host>:4222"}
    ]
  },
  "endpoints": {
    "http": {"port": 8080, "type": "REST", "visibility": ["external"]}
  },
  "dependencies": {
    "endpoints": [
      {"name": "tcp", "component": "doclet-postgres", "visibility": "project"},
      {"name": "tcp", "component": "doclet-nats",     "visibility": "project"}
    ]
  }
}
```

**Note:** No `envBindings` on the TCP dependencies. The injected `address` value is `host:port` — not a Postgres DSN. The full DSN is set as an explicit env var instead.

### collab-svc (after source build)

```json
{
  "container": {
    "image": "<built-image-from-ecr>",
    "env": [
      {"key": "DOCLET_COLLAB_ADDR", "value": ":8090"},
      {"key": "DOCLET_NATS_URL",    "value": "nats://<nats-host>:4222"}
    ]
  },
  "endpoints": {
    "http": {"port": 8090, "type": "Websocket", "visibility": ["external"]}
  },
  "dependencies": {
    "endpoints": [
      {"name": "tcp", "component": "doclet-nats", "visibility": "project"}
    ]
  }
}
```

**Note:** WebSocket endpoint type is `"Websocket"` (capital W, lowercase s) — not `"WebSocket"`.

### doclet-frontend (after source build)

> Replace `<doc-svc-url>` and `<collab-svc-url>` with `externalURLs.http` values (using `https://` and `wss://` schemes).

```json
{
  "container": {
    "image": "<built-image-from-ecr>",
    "files": [
      {
        "key": "config.json",
        "mountPath": "/usr/share/nginx/html",
        "value": "{\"docServiceUrl\":\"https://<doc-svc-url>\",\"collabWsUrl\":\"wss://<collab-svc-url>\"}"
      }
    ]
  },
  "endpoints": {
    "http": {"port": 80, "type": "HTTP", "visibility": ["external"]}
  },
  "dependencies": {
    "endpoints": [
      {"name": "http", "component": "document-svc", "visibility": "project"},
      {"name": "http", "component": "collab-svc",   "visibility": "project"}
    ]
  }
}
```

**Note:** `mountPath` is set to the **directory** (`/usr/share/nginx/html`), not the full file path. The controller appends the `key` name to form the final path. Setting `mountPath` to the full path results in `config.json/config.json`.

---

## Known issues and gotchas discovered during this run

### 1. TCP `address` envBinding injects `host:port`, not a DSN

**Symptom:** App crash-loops before logging "listening" — database or broker connection fails immediately.

**Root cause:** OpenChoreo injects `host:port` (e.g. `doclet-postgres.dp-default-doclet-development-50ce4d9b.svc.cluster.local:5432`) for TCP connections. Apps expecting a full DSN (`postgres://user:pass@host/db` or `nats://host:4222`) cannot parse it.

**Fix:** Do not set `envBindings` on TCP dependencies. Declare the dependency for the cell diagram, then set the full DSN as a literal env var using the `serviceURL.host` from `get_release_binding`.

### 2. File mount `mountPath` must be a directory

**Symptom:** File appears at `config.json/config.json` instead of `config.json`.

**Root cause:** The controller appends the `key` name to `mountPath`. Setting `mountPath` to the full file path doubles the filename.

**Fix:** Set `mountPath` to the parent directory only.

### 3. Mixed content: frontend served over HTTPS needs `https://` and `wss://`

**Symptom:** API calls and WebSocket connections silently fail — no visible error in the app, but nothing works.

**Root cause:** OpenChoreo serves `web-application` components over HTTPS. Browsers block HTTP/WS requests from HTTPS pages as mixed content.

**Fix:** Get external URLs from `get_release_binding` → `endpoints[*].externalURLs` and replace the scheme with `https://` or `wss://`.

### 4. `update_workload` requires `image` in the spec

**Symptom:** `update_workload` fails with `spec.container.image in body should be at least 1 chars long`.

**Fix:** Always call `get_workload` first to retrieve the current image tag, then include it in the update spec.

### 5. `update_workload` does not accept `project_name` or `component_name`

**Symptom:** Tool rejects the call with unexpected parameter errors.

**Fix:** Only pass `namespace_name`, `workload_name`, and `workload_spec`. Use `list_workloads` to find the workload name.

---

## Results

| Metric | Value |
|---|---|
| Components deployed | 5 / 5 |
| All components Ready | Yes |
| Build method | 2 × BYO, 3 × source (dockerfile-builder) |
| Frontend external URL | `http://http-doclet-fronte-development-default-<hash>.apps.aws.openchoreo-poc.choreo.dev` |
| End-to-end deployment time | ~10 min |

---

## Screenshots

### Cell diagram — service topology

![Cell diagram](screenshots/cell-diagram.png)

### Web interface — Doclet in action

![Web interface](screenshots/web-interface.png)

---

## Tips for reuse

- **BYO for infrastructure (databases, brokers)** — no source build needed; just provide the image and declare TCP endpoints with `visibility: project`
- **TCP connections: set explicit env vars, not `envBindings`** — for any service that expects a DSN (Postgres, MySQL, NATS, Redis), skip `envBindings` and set the full connection string as a literal env var
- **Always call `update_workload` after source builds with no `workload.yaml`** — the build step only produces a minimal workload with the image; endpoints, env vars, file mounts, and dependencies must be added separately
- **SPAs with runtime config: mount as a file, not baked into the image** — this lets you update backend URLs without rebuilding; set `mountPath` to the nginx html directory, not the full file path
- **Use `get_release_binding` as the source of truth for URLs** — internal `serviceURL.host` for service-to-service, external `externalURLs` for browser-facing URLs
- **Component names must be unique across the namespace** — prefix infra components with the project name (e.g. `doclet-postgres`, not `postgres`) to avoid conflicts with other projects
