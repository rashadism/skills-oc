# `occ` CLI and Platform Resources — PE Reference

PE-specific `occ` commands, platform resource creation patterns, and the YAML shapes for plane resources. For install, login, context, the full command table, and universal gotchas, see `openchoreo-core/references/cli.md`.

## PE Command Quick Reference

| Command | Alias | What it does |
|---|---|---|
| `occ dataplane list/get` | `dp` | Inspect DataPlane CRs |
| `occ workflowplane list/get` | `wp` | Inspect WorkflowPlane CRs (formerly BuildPlane) |
| `occ observabilityplane list/get` | `op` | Inspect ObservabilityPlane CRs |
| `occ environment list/get` | `env` | Inspect Environments |
| `occ deploymentpipeline list/get` | `deppipe` | Inspect promotion paths |
| `occ componenttype list/get` | `ct` | Inspect namespace-scoped types |
| `occ clustercomponenttype list/get` | `cct` | Inspect cluster-scoped types |
| `occ trait list/get` | `traits` | Inspect namespace-scoped traits |
| `occ clustertrait list/get` | `clustertraits` | Inspect cluster-scoped traits |
| `occ workflow list/get` | `wf` | Inspect workflow templates |
| `occ clusterauthzrole list/get` | `car` | Inspect cluster roles |
| `occ clusterauthzrolebinding list/get` | `carb` | Inspect cluster role bindings |
| `occ authzrole list/get` | — | Inspect namespace roles |
| `occ authzrolebinding list/get` | `rb` | Inspect role bindings |
| `occ apply -f <file>` | — | Create/update any resource |
| `occ namespace list/get` | `ns` | Inspect namespaces |

## Creating Platform Resources

Most platform resources have no MCP create tool — use `occ apply -f` or, where called out, `kubectl apply -f`. `occ` must be installed and logged in first (see `openchoreo-core/references/cli.md`).

> **Gotcha**: `occ apply -f -` (stdin) does not work — error `path - does not exist`. Write YAML to a temp file first, then apply.

### Create an Environment

```bash
cat > /tmp/env.yaml <<'EOF'
apiVersion: openchoreo.dev/v1alpha1
kind: Environment
metadata:
  name: qa
  namespace: default
  labels:
    openchoreo.dev/name: qa
  annotations:
    openchoreo.dev/display-name: QA
    openchoreo.dev/description: QA
spec:
  dataPlaneRef:
    kind: DataPlane
    name: default
  isProduction: false
EOF
occ apply -f /tmp/env.yaml
```

Set `isProduction: true` for production environments.

### Create a DeploymentPipeline

> **Known bug**: `occ apply -f` fails for `DeploymentPipeline` — the occ client model and the API server schema disagree on whether `sourceEnvironmentRef` is a plain string or an object. Use **`kubectl apply -f`** instead.

```bash
cat > /tmp/pipeline.yaml <<'EOF'
apiVersion: openchoreo.dev/v1alpha1
kind: DeploymentPipeline
metadata:
  name: foo-pipeline
  namespace: default
  labels:
    openchoreo.dev/name: foo-pipeline
  annotations:
    openchoreo.dev/display-name: Foo Pipeline
    openchoreo.dev/description: "development → qa → production"
spec:
  promotionPaths:
    - sourceEnvironmentRef: development
      targetEnvironmentRefs:
        - name: qa
    - sourceEnvironmentRef: qa
      targetEnvironmentRefs:
        - name: production
EOF
kubectl apply -f /tmp/pipeline.yaml   # use kubectl, not occ apply
```

> **Important**: The `openchoreo.dev/name` label must be set on the pipeline metadata or it may not be discoverable via the API.

### Create or Update a Project

> **Preferred**: Use the `create_project` MCP tool — it accepts a `deployment_pipeline` parameter so the correct pipeline can be set at creation time without `occ apply`.

```
create_project(namespace, name, deployment_pipeline="foo-pipeline")
```

Use `occ apply` only when you also need display name / description annotations:

```bash
cat > /tmp/project.yaml <<'EOF'
apiVersion: openchoreo.dev/v1alpha1
kind: Project
metadata:
  name: foo
  namespace: default
  labels:
    openchoreo.dev/name: foo
  annotations:
    openchoreo.dev/display-name: Foo
spec:
  deploymentPipelineRef:
    kind: DeploymentPipeline
    name: foo-pipeline
EOF
occ apply -f /tmp/project.yaml
```

### Verify after applying

```bash
occ environment list
occ deploymentpipeline list
occ project list
```

## Plane Resource Schemas

These YAML shapes are used with `kubectl apply` or `occ apply` — there are no MCP CRUD tools for plane resources.

### Namespace

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Namespace
metadata:
  name: my-org
```

### DataPlane

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: DataPlane                     # also ClusterDataPlane
metadata:
  name: default
  namespace: default
spec:
  planeID: default                  # must match agent Helm value
  clusterAgent:
    clientCA:
      value: |                      # agent's CA certificate (PEM)
        -----BEGIN CERTIFICATE-----
        ...
        -----END CERTIFICATE-----
  gateway:
    publicVirtualHost: "apps.example.com"
    organizationVirtualHost: "internal.example.com"
    publicHTTPPort: 80
    publicHTTPSPort: 443
    ingress:
      external:
        name: gateway-default
        namespace: openchoreo-data-plane
        http:
          host: openchoreoapis.localhost
          port: 19080
          listenerName: http
  secretStoreRef:
    name: default
  observabilityPlaneRef:
    name: default
```

### WorkflowPlane (formerly BuildPlane)

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: WorkflowPlane                 # also ClusterWorkflowPlane
metadata:
  name: default
  namespace: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
        -----BEGIN CERTIFICATE-----
        ...
        -----END CERTIFICATE-----
  secretStoreRef:
    name: default
```

### ObservabilityPlane

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ObservabilityPlane            # also ClusterObservabilityPlane
metadata:
  name: default
  namespace: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
        -----BEGIN CERTIFICATE-----
        ...
        -----END CERTIFICATE-----
  observerURL: "https://observer.example.com"
```

### ObservabilityAlertsNotificationChannel

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ObservabilityAlertsNotificationChannel
metadata:
  name: email-alerts
  namespace: default
spec:
  environment: development
  isEnvDefault: true
  type: email                        # email | webhook
  emailConfig:
    from: alerts@example.com
    to: ["team@example.com"]
    smtp:
      host: smtp.example.com
      port: 587
      auth:
        username:
          secretKeyRef: {name: smtp-creds, key: username}
        password:
          secretKeyRef: {name: smtp-creds, key: password}
```

For ComponentType, Trait, and Workflow schemas, see `templates-and-workflows.md`. For Project, Environment, DeploymentPipeline, ReleaseBinding, and Workload shapes, see `openchoreo-core/references/resource-schemas.md`.
