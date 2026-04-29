# Connect components (endpoint dependencies)

Wire one Component to another's endpoint so OpenChoreo injects the resolved service address as an env var. Uses `spec.dependencies.endpoints[]` on the consuming Workload.

> **Tool surface preference: MCP first, `occ` CLI as fallback.** Same as every recipe in this skill.

## When to use

- One component needs to call another component's endpoint
- The user is hardcoding hostnames or guessing service DNS — replace with a dependency
- Cross-project dependencies (e.g. an app calling a shared `auth-service` in a `platform-services` project)
- For attaching plain env vars or secrets unrelated to other components, use `recipes/configure-workload.md` / `recipes/manage-secrets.md`

## Prerequisites

1. Both Components exist and the **target's endpoint visibility is broad enough** for the consumer:

| Consumer asks for | Target endpoint must declare at least |
|---|---|
| same project | `project` (implicit) |
| different project, same namespace | `namespace` |
| different namespace | `internal` |

2. Visibility is a *list*, so a target endpoint can have e.g. `[namespace, external]` and serve both same-project and cross-project consumers.

To inspect a target's endpoint visibility:

```
mcp__openchoreo-cp__get_workload
  namespace_name: default
  workload_name: <target>-workload
```

## Recipe — MCP (preferred)

### 1. Read the consuming Workload

```
mcp__openchoreo-cp__get_workload
  namespace_name: default
  workload_name: frontend-workload
```

### 2. Add `dependencies.endpoints[]` and update

Send the full updated `workload_spec` with a new `dependencies` block:

```
mcp__openchoreo-cp__update_workload
  namespace_name: default
  workload_name: frontend-workload
  workload_spec:
    owner: {projectName: default, componentName: frontend}
    container: {...}                  # unchanged from the read
    endpoints: {...}                  # unchanged from the read
    dependencies:
      endpoints:
        - component: user-service     # target component name
          name: http                  # target endpoint name (NOT "endpoint")
          visibility: project
          envBindings:
            address: USER_SERVICE_URL
```

OpenChoreo injects `USER_SERVICE_URL` (and any other env vars in `envBindings`) into the consumer's container at runtime. The dependency makes a new ComponentRelease.

### 3. Verify after redeploy

Once the redeploy is `Ready`, fetch runtime logs and confirm the env var resolves:

```
mcp__openchoreo-obs__query_component_logs
  namespace: default
  component: frontend
  start_time: <RFC3339>
  end_time: <RFC3339>
  search_phrase: USER_SERVICE_URL
```

For deeper inspection, see `recipes/inspect-and-debug.md`.

## Recipe — `occ` CLI (fallback)

### 1. Read the consuming Workload

```bash
occ workload get frontend-workload --namespace default
```

### 2. Edit the YAML and apply

Add the `dependencies` block under `spec`, then:

```bash
occ apply -f /tmp/frontend-workload.yaml
```

### 3. Verify

```bash
occ component logs frontend --namespace default
```

## Patterns

### Same-project dependency

```yaml
dependencies:
  endpoints:
    - component: user-service
      name: http
      visibility: project              # implicit default; same project, same env
      envBindings:
        address: USER_SERVICE_URL
```

### Cross-project dependency

```yaml
dependencies:
  endpoints:
    - component: shared-auth-service
      name: http
      visibility: namespace            # broader than project
      project: platform-services       # required when target is in a different project
      envBindings:
        address: AUTH_SERVICE_URL
        host: AUTH_SERVICE_HOST
        port: AUTH_SERVICE_PORT
```

The target's `endpoints.http.visibility` must include `namespace` (or broader).

### Multiple dependencies

```yaml
dependencies:
  endpoints:
    - component: user-service
      name: http
      visibility: project
      envBindings:
        address: USER_SERVICE_URL
    - component: notification-service
      name: grpc
      visibility: project
      envBindings:
        address: NOTIFICATION_SERVICE_ADDR
    - component: analytics-api
      name: http
      visibility: namespace
      project: analytics
      envBindings:
        address: ANALYTICS_API_URL
        basePath: ANALYTICS_API_BASE_PATH
```

## envBindings keys

Each binding takes one or more of:

| Key | Injects | Example value |
|---|---|---|
| `address` | full address | `http://user-service.default.svc.cluster.local:9090/api` |
| `host` | hostname only | `user-service.default.svc.cluster.local` |
| `port` | port number only | `9090` |
| `basePath` | base path only (HTTP only) | `/api` |

The format of `address` depends on the endpoint type:

- HTTP / WebSocket: `scheme://host:port/basePath`
- gRPC / TCP / UDP: `host:port`

The right side of each `envBindings` entry is the env var name in the consumer.

## Gotchas

- **Dependencies live at `spec.dependencies.endpoints[]`, not flat `spec.dependencies[]` or `spec.connections[]`.** The pre-v1.0.0 flat shape is gone. Each entry uses `name` for the target endpoint name — not `endpoint`.
- **`update_workload` sends the full spec** — read first, append the dependency, send back. See `recipes/configure-workload.md` for the same gotcha.
- **Visibility mismatch is silent until reconcile.** `update_workload` accepts a dependency whose target visibility is too narrow, but the ReleaseBinding fails to bind. Check `status.conditions` on the ReleaseBinding for the actual error.
- **Cross-project dependencies require both `visibility: namespace` (or broader) and `project: <name>`.** Missing `project` defaults to the same project — the binding fails with "endpoint not found" because the controller looks in the wrong project.
- **Consumer's visibility request can't exceed the target's declaration.** Asking for `internal` against a target that only declares `[namespace]` fails. Either lower the consumer's `visibility` or have the target add `internal` to its endpoint visibility.
- **Max 50 endpoint dependencies per Workload.** A consumer pulling from more than 50 components is a design smell — split it.
- **Connection refused after deploy?** Confirm the target's endpoint visibility list includes the level the consumer is asking for. Most "it deployed but can't connect" issues trace to this.
- **The injected `address` already includes the scheme (HTTP/WS).** Don't prepend `http://` in the consumer's code when using `address`. If you need just the host, use `envBindings.host` instead.

## Related recipes

- [`configure-workload.md`](configure-workload.md) — endpoint visibility, env vars, files
- [`manage-secrets.md`](manage-secrets.md) — secret-referenced env vars (for credentials, not service addresses)
- [`inspect-and-debug.md`](inspect-and-debug.md) — verify the env var injected and the connection succeeded
- [`deploy-and-promote.md`](deploy-and-promote.md) — promotion across environments preserves dependency wiring
