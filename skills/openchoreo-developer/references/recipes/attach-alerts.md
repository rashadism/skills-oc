# Attach observability alerts

Attach the `observability-alert-rule` trait to a Component so OpenChoreo fires log- or metric-based alerts when conditions are met. Per-environment notification channels are wired through the ReleaseBinding.

> **Trait *attachment* on the Component has no MCP write surface.** Hand off to `openchoreo-platform-engineer` to apply the Component spec change. The trait's *per-environment configuration* (channels, enabled, thresholds) is on the ReleaseBinding and stays in this skill via `update_release_binding`.

## When to use

- Page on error log spikes, high CPU/memory, or a custom log query
- Different notification channels per environment (email in dev, Slack in prod)
- Enable AI root-cause analysis on incidents
- For viewing already-fired alerts/incidents (read-only inspection), see the bottom of this recipe

Channel and incident infrastructure is **PE-owned** — the developer attaches the trait; the platform must have an `ObservabilityAlertsNotificationChannel` configured per environment. If apply succeeds but no alerts arrive, escalate.

## Prerequisites

1. The target environment has a notification channel configured. List existing references:
   ```
   query_alerts
     namespace: default
     start_time: <RFC3339>
     end_time:   <RFC3339>
   ```
   (Used to confirm alerts are flowing once attached. Channel-resource discovery on the platform side is PE territory.)
2. The Component already exists. If not, deploy first via `recipes/deploy-prebuilt-image.md` or `recipes/build-from-source.md`.

## Recipe — define the alert on the Component

The trait attaches in the Component's `spec.traits[]`. **No MCP write surface for this** — author the spec here, then hand off to `openchoreo-platform-engineer` to apply.

### 1. Discover the trait's parameter schema

```
list_cluster_traits
get_cluster_trait_schema
  ct_name: observability-alert-rule
```

### 2. Author the Component spec with the trait attached

Copy `assets/component-with-alert-trait.yaml` and edit. The trait has these top-level parameter fields:

| Field | Required | Description |
|---|---|---|
| `description` | yes | Human-readable summary; appears in notifications |
| `severity` | no (default `warning`) | `info` / `warning` / `critical` |
| `source.type` | yes | `log` or `metric` |
| `source.query` | conditional | log query expression — required if `type: log` |
| `source.metric` | conditional | metric name — required if `type: metric`. One of: `cpu_usage`, `memory_usage` |
| `condition.window` | no (default `5m`) | rolling time window |
| `condition.interval` | no (default `1m`) | how often the rule is evaluated |
| `condition.operator` | no (default `gt`) | `gt` / `lt` / `gte` / `lte` / `eq` |
| `condition.threshold` | no (default `10`) | numeric threshold |

```yaml
spec:
  traits:
    - kind: ClusterTrait
      name: observability-alert-rule
      instanceName: high-error-rate-log-alert      # unique per Component
      parameters:
        description: "Error logs exceed threshold over 5m window"
        severity: critical
        source: {type: log, query: "status:error"}
        condition: {window: 5m, interval: 1m, operator: gt, threshold: 50}
```

A Component can attach the same trait multiple times with different `instanceName`s — e.g. one log-based alert and one metric-based alert.

### 3. Hand off to platform-engineer for apply

Activate `openchoreo-platform-engineer` with the authored Component spec — that skill has the surface to apply it.

### 4. Verify

```
get_component
  namespace_name: default
  component_name: my-service
```

Look at `status.conditions[]` for `Reconciled: True`, then check `spec.traits[]` echoed back to confirm the attachment.

## Recipe — configure per-environment channels

The trait *defines* what to alert on. Channels — *where* alerts go — are configured per-environment via `traitEnvironmentConfigs` on the ReleaseBinding.

```
update_release_binding
  namespace_name: default
  binding_name: my-service-production
  trait_environment_configs:
    high-error-rate-log-alert:                # the trait's instanceName
      enabled: true
      actions:
        notifications:
          channels:
            - devops-slack-prod
            - oncall-email-prod
        incident:
          enabled: true
          triggerAiRca: false
```

If `channels` is omitted, the environment's default channel is used (the first channel created in that env is auto-marked default).

### Disable the alert in some environments

```yaml
trait_environment_configs:
  high-error-rate-log-alert:
    enabled: false
```

## Patterns

### Log-based alert

```yaml
parameters:
  description: "5xx response rate elevated"
  severity: critical
  source:
    type: log
    query: "level:error AND status:5*"
  condition: {window: 5m, interval: 1m, operator: gt, threshold: 100}
```

### Metric-based alert

```yaml
parameters:
  description: "CPU sustained above 80%"
  severity: warning
  source:
    type: metric
    metric: cpu_usage
  condition: {window: 5m, interval: 1m, operator: gt, threshold: 80}
```

### Different channels per environment

Attach the trait once on the Component (instanceName: `high-error-rate`). Then in each environment's ReleaseBinding, override `actions.notifications.channels[]` to the channel(s) appropriate for that env.

### Enable AI RCA (incidents only)

```yaml
trait_environment_configs:
  high-error-rate:
    actions:
      incident:
        enabled: true
        triggerAiRca: true        # requires incident.enabled: true
```

## View alerts and incidents

Read-only — agent / user inspection.

```
query_alerts
  namespace: default
  project: default
  component: my-service
  start_time: <RFC3339>
  end_time:   <RFC3339>
```

```
query_incidents
  namespace: default
  project: default
  component: my-service
  start_time: <RFC3339>
  end_time:   <RFC3339>
```

Acknowledging and resolving incidents is done through the Backstage portal — there is no MCP write surface for incident state changes.

## Gotchas

- **No MCP for Component trait attachment** — hand off to `openchoreo-platform-engineer` to apply the Component spec change. The trait's *per-environment configuration* (channels, enabled, etc.) stays in this skill via `update_release_binding`.
- **`triggerAiRca: true` requires `incident.enabled: true`.** Standalone AI RCA without an incident is invalid; the controller rejects it.
- **Without a notification channel, the ReleaseBinding fails to apply the trait.** Either a channel exists in the env (and is referenced in `actions.notifications.channels[]` or used as the env default), or the alert never fires anywhere reachable. If apply succeeds but no alerts arrive, the channel is the first thing to check (PE side).
- **`instanceName` must be unique per Component** — but the same `name: observability-alert-rule` can repeat across different `instanceName`s. The override key in `trait_environment_configs` is the `instanceName`.
- **`source.metric` is a fixed enum**, currently `cpu_usage` or `memory_usage`. For arbitrary metrics, use `type: log` with a metric-derived log query, or escalate to PE for a custom rule.
- **`condition.window` and `condition.interval` should be coherent.** Interval shorter than the window means each evaluation includes overlapping data; that's usually intentional. Interval longer than the window means gaps in coverage.
- **The first channel created in an env is auto-default.** If you don't pass `channels[]`, that's where the alert goes. Confirm this matches what you want for prod.
- **Alerts query against the observability plane.** If `query_alerts` returns nothing right after first deploy, give it the trait's `interval` to fire once before declaring it broken.

## Related recipes

- [`configure-workload.md`](configure-workload.md) — Trait attachment patterns in general
- [`override-per-environment.md`](override-per-environment.md) — `traitEnvironmentConfigs` shape and rules
- [`inspect-and-debug.md`](inspect-and-debug.md) — manual triage when alerts fire
- [`deploy-and-promote.md`](deploy-and-promote.md) — promotion preserves trait attachment but per-env trait config does not propagate
