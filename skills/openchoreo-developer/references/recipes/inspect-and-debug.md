# Inspect and debug

Read runtime logs, check status conditions, fetch pod-level events, and diagnose common deploy failures (CrashLoopBackOff, ImagePullBackOff, NotReady).

> **Tool surface preference: MCP first, `occ` CLI as fallback.** Same as every recipe in this skill.

## When to use

- "Is my deploy working?" — verify after `recipes/deploy-prebuilt-image.md`, `recipes/build-from-source.md`, or `recipes/deploy-and-promote.md`
- "Why isn't it working?" — service is `NotReady`, pods are crashing, endpoints aren't reachable
- Routine log-reading during development
- Triage before deciding whether to escalate to PE

This recipe is read-only. For mutating recovery (rollback, redeploy), see `recipes/deploy-and-promote.md`.

## Status hierarchy

```
Component (control plane)
  └─ ComponentRelease (control plane)
       └─ ReleaseBinding (control plane → data plane)
            └─ Deployment / Pod / Service / HTTPRoute (data plane)
```

Inspect top-down. The most specific signal — a pod's events or container logs — usually says what's wrong; higher levels just tell you which environment to look in.

## Recipe — check status

### Component-level (resource conditions)

```
mcp__openchoreo-cp__get_component
  namespace_name: default
  component_name: my-service
```

Look at `status.conditions[]`:

| Condition type | Healthy value | Means |
|---|---|---|
| `Ready` | `True` | Component overall is reconciled |
| `Reconciled` | `True` | Controller picked up the latest spec |

```
mcp__openchoreo-cp__get_workload
  namespace_name: default
  workload_name: my-service-workload
```

### ReleaseBinding-level (per-environment health)

```
mcp__openchoreo-cp__list_release_bindings
  namespace_name: default
  component_name: my-service

mcp__openchoreo-cp__get_release_binding
  namespace_name: default
  binding_name: my-service-development
```

| Condition type | Healthy value | Means |
|---|---|---|
| `Ready` | `True` | Binding is up |
| `Deployed` | `True` | Resources reached the data plane |
| `Synced` | `True` | Data plane matches the spec |

`status.endpoints[]` holds the deployed URLs.

### CLI equivalents

```bash
occ component get my-service --namespace default
occ workload get my-service-workload --namespace default
occ releasebinding list --namespace default --project default --component my-service
occ releasebinding get my-service-development --namespace default
```

## Recipe — runtime logs

### MCP (preferred for log queries — supports filters, search, pagination)

```
mcp__openchoreo-obs__query_component_logs
  namespace: default
  project: default
  component: my-service
  environment: development           # optional — omit to query all envs
  start_time: 2026-04-29T00:00:00Z
  end_time:   2026-04-29T01:00:00Z
  log_levels: ["ERROR", "WARN"]      # optional — defaults to all
  search_phrase: "connection refused" # optional
  limit: 100                          # default 100
  sort_order: desc                    # default desc
```

Both `start_time` and `end_time` are required and must be RFC3339.

### CLI

```bash
occ component logs my-service --namespace default --project default
occ component logs my-service -f                            # follow / tail
occ component logs my-service --env production
occ component logs my-service --tail 100
occ component logs my-service --since 1h
```

## Recipe — pod-level inspection

When component-level logs are empty (the container never started) or you need K8s events.

### Resource events for a binding

```
mcp__openchoreo-cp__get_resource_events
  namespace_name: default
  release_binding_name: my-service-development
  group: apps
  version: v1
  kind: Deployment
  resource_name: my-service          # the Deployment name in the data plane
```

Use this for `ImagePullBackOff`, scheduling failures, OOM kills, etc. — events the pod logs can't show.

### Pod logs (for crashlooping containers where component logs are empty)

```
mcp__openchoreo-cp__get_resource_logs
  namespace_name: default
  release_binding_name: my-service-development
  pod_name: my-service-7f9c-abc12
  since_seconds: 300                 # last 5 minutes
```

To find the pod name, fetch resource events on the Pod kind first or list bindings — the binding status surfaces the running pods.

## Recipe — investigate a crashloop

A reusable flow when "the deploy says Ready but the app isn't responding" or "Component is NotReady":

1. **Component conditions** — `get_component`, look at `status.conditions[]`. If `Ready: False`, read the `message` field for the reason.
2. **ReleaseBinding conditions** — `get_release_binding`. If `Deployed: True` but `Synced: False`, the data plane is mid-rollout; wait, then re-check.
3. **Resource events on the Deployment** — `get_resource_events` with `kind: Deployment`. Look for image pull errors, quota issues, scheduling problems.
4. **Resource events on the Pod** — same call with `kind: Pod`, `resource_name: <pod name>`. Look for `BackOff`, `Killed`, `OOMKilled`.
5. **Pod logs** — `get_resource_logs` to read the crashing container's stderr.
6. **Component logs** — `query_component_logs` with `log_levels: [ERROR]` and a recent time window.

If the cause is in the application (bad config, missing env var, dependency unreachable), it's a developer fix. If the cause is plane-level (data plane disconnected, controller stuck, gateway misconfigured), escalate to `openchoreo-platform-engineer`.

## Common failure matrix

| Symptom | Likely cause | First check |
|---|---|---|
| Component stuck `NotReady` | Data plane connectivity | `get_release_binding` status, then escalate to PE if data-plane side |
| Pod `CrashLoopBackOff` | Application error / bad config | `get_resource_logs` then `query_component_logs` with `ERROR` level |
| `ImagePullBackOff` | Wrong image URL or missing credentials | `get_resource_events` on the Pod for the exact error; for private registry, see `recipes/deploy-prebuilt-image.md` |
| Endpoint URL not reachable | HTTPRoute not created or gateway misconfigured | `get_release_binding` `status.endpoints[]` first; if missing, escalate to PE |
| Deployment doesn't appear | ReleaseBinding never created | `list_release_bindings` — if empty, see `recipes/deploy-and-promote.md` |
| Pod `OOMKilled` | Memory limit too low | `get_resource_events` for the kill, then `recipes/override-per-environment.md` to bump `resources.limits.memory` |
| Pod `Pending` long time | Cluster resource pressure or scheduling | `get_resource_events` on the Pod; PE concern if cluster-wide |

## Metrics and traces (optional)

For runtime metrics and distributed traces, the observer MCP server exposes:

```
mcp__openchoreo-obs__query_resource_metrics       # CPU, memory, network
mcp__openchoreo-obs__query_http_metrics           # HTTP-level (request rate, latency, status codes)
mcp__openchoreo-obs__query_traces                 # tracing spans
mcp__openchoreo-obs__query_trace_spans
mcp__openchoreo-obs__get_span_details
mcp__openchoreo-obs__query_alerts                 # active alerts
mcp__openchoreo-obs__query_incidents              # incident history
```

All take a `namespace`, scoping filters (`project`, `component`, `environment`), and `start_time` / `end_time` (RFC3339). Use these when logs alone don't explain the symptom — e.g. P99 latency spikes, request error rates, or a downstream service slowing the trace.

## Gotchas

- **`status.conditions` is the source of truth.** Don't infer from indirect signals (e.g. logs not appearing) — read the conditions first.
- **Component logs are empty when the container can't start.** `ImagePullBackOff` and similar leave nothing in the pod's stdout. Switch to `get_resource_events` for those.
- **Both `start_time` and `end_time` are required for log/metric queries** and must be RFC3339 (e.g. `2026-04-29T08:29:02Z`). Off-by-one timezone bugs are common; prefer UTC `Z` suffix.
- **`Ready: True` briefly during rollout.** A pod can flap to `Ready` for a few seconds before crashing again. Always confirm with logs that the app actually started.
- **`get_resource_logs` needs a known `pod_name`.** There's no `list_pods` MCP. Get the name from the binding's status, or from `get_resource_events` (events list pod names in `involvedObject`).
- **Per-environment logs filter via the `environment` param**, not by binding name. A single component running in dev + staging produces logs in two environments.
- **Promotion preserves the failure mode.** If a release is broken in dev, promoting it deploys the same broken release to staging. Rollback first (`recipes/deploy-and-promote.md`) before re-promoting.

## Related recipes

- [`deploy-prebuilt-image.md`](deploy-prebuilt-image.md) / [`build-from-source.md`](build-from-source.md) — what produced the running release
- [`deploy-and-promote.md`](deploy-and-promote.md) — rollback once you've identified a bad release
- [`configure-workload.md`](configure-workload.md) / [`override-per-environment.md`](override-per-environment.md) — fix the underlying config
- [`attach-alerts.md`](attach-alerts.md) — set up alerts so you don't depend on manual log inspection
