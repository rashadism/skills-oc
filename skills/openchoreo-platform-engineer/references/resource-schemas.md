# OpenChoreo Resource Schemas

All resources use `apiVersion: openchoreo.dev/v1alpha1`.

Prefer `occ component scaffold` or a matching sample from `samples/` before hand-writing YAML. Inspect the live cluster schema with the relevant MCP tool (`get_cluster_component_type_schema`, `get_workload_schema`, etc.) when unsure of a field shape.

This file holds **universal** resource schemas — those any OpenChoreo workflow needs. Plane resource shapes (`DataPlane`, `WorkflowPlane`, `ObservabilityPlane`, `ObservabilityAlertsNotificationChannel`) are install-time concerns; consult the official PE guide at https://openchoreo.dev/docs/platform-engineer-guide/ for those.

## Project

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Project
metadata:
  name: my-project
  namespace: default
spec:
  deploymentPipelineRef:
    kind: DeploymentPipeline
    name: default
```

> **Important**: `deploymentPipelineRef` is an object with `kind` and `name` fields (changed in v1.0.0 — previously a plain string).

## Component

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Component
metadata:
  name: my-app
  namespace: default
  annotations:
    openchoreo.dev/display-name: "My Application"
    openchoreo.dev/description: "Backend API service"
spec:
  owner:
    projectName: my-project
  autoDeploy: true
  componentType:
    kind: ClusterComponentType        # or ComponentType for namespace-scoped
    name: deployment/service
  parameters: {}
  traits:
    - name: persistent-volume
      kind: ClusterTrait              # or Trait for namespace-scoped
      instanceName: storage
      parameters:
        volumeName: data
        mountPath: /var/data
  workflow:
    kind: ClusterWorkflow             # or Workflow for namespace-scoped
    name: dockerfile-builder
    parameters:
      repository:
        url: "https://github.com/org/repo"
        revision:
          branch: "main"
        appPath: "."
      docker:
        context: "."
        filePath: "./Dockerfile"
```

**Notes**:
- Source builds use `spec.workflow`, not `spec.build`.
- The `workflow.parameters` shape is determined by the workflow's `openAPIV3Schema`. The example above is for `dockerfile-builder`; other workflows have different shapes. Always inspect with `occ clusterworkflow get <name>` (or `occ workflow get <name>`) before authoring.
- `componentType.name` is always `{workloadType}/{typeName}`.
- `componentType.kind` and `workflow.kind` default to the cluster-scoped variant (`ClusterComponentType`, `ClusterWorkflow`). Set explicitly when using namespace-scoped types/workflows.
- `repository.appPath` selects the service subdirectory and `workload.yaml`. `docker.context` and `docker.filePath` must still point at real repo-root-relative Docker build paths.
- For BYO image deployments, **omit `spec.workflow`** entirely.

## Workload

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Workload
metadata:
  name: my-app-workload
  namespace: default
spec:
  owner:
    projectName: my-project
    componentName: my-app
  container:
    image: myregistry/my-app:v1.0.0
    command: ["/app/server"]
    args: ["--port", "8080"]
    env:
      - key: LOG_LEVEL
        value: info
      - key: DB_PASSWORD
        valueFrom:
          secretKeyRef:
            name: db-secrets
            key: password
    files:
      - key: config.yaml
        mountPath: /etc/app/config.yaml
        value: |
          port: 8080
      - key: cert.pem
        mountPath: /etc/ssl/cert.pem
        valueFrom:
          secretKeyRef:
            name: tls-certs
            key: cert
  endpoints:
    api:
      type: HTTP                      # HTTP | GraphQL | Websocket | gRPC | TCP | UDP
      port: 8080
      targetPort: 8080
      visibility: ["external"]
      basePath: "/api/v1"
      displayName: "REST API"
      schema:
        content: |
          openapi: 3.0.0
          info:
            title: My API
            version: 1.0.0
    metrics:
      type: HTTP
      port: 9090
  dependencies:
    endpoints:
      - project: other-project        # optional; defaults to same project
        component: backend-api
        name: api                     # name of the target endpoint
        visibility: project            # project | namespace
        envBindings:
          address: BACKEND_URL
          host: BACKEND_HOST
          port: BACKEND_PORT
          basePath: BACKEND_PATH
```

`endpoints` is a **map** keyed by endpoint name (`api`, `metrics`, …). Allowed `type` values: `HTTP`, `GraphQL`, `Websocket`, `gRPC`, `TCP`, `UDP`. Every endpoint implicitly has `project` visibility — the `visibility` array adds `namespace`, `internal`, or `external`.

`dependencies.endpoints` is a **list** of connections to other components' endpoints. Field names: `component`, `name` (target endpoint name), `visibility`, `envBindings`. Optional `project` defaults to the same project.

For reverse proxies, prefer `host` and `port` bindings unless you explicitly want the endpoint `basePath` included in the upstream URL.

## Workload Descriptor (`workload.yaml`)

Used for source builds. Place at the root of the `appPath` directory.

```yaml
apiVersion: openchoreo.dev/v1alpha1

metadata:
  name: my-service

endpoints:                          # list (in the descriptor only — the Workload CR uses a map)
  - name: api
    port: 8080
    type: HTTP                      # HTTP | GraphQL | Websocket | gRPC | TCP | UDP
    targetPort: 8080
    displayName: "REST API"
    basePath: "/api/v1"
    schemaFile: openapi.yaml        # relative path, content is inlined by build
    visibility:
      - external

dependencies:
  endpoints:                        # nested under .endpoints
    - project: other-project        # optional; defaults to same project
      component: backend-api
      name: api                     # name of the target endpoint
      visibility: project
      envBindings:
        address: BACKEND_URL
        host: BACKEND_HOST
        port: BACKEND_PORT
        basePath: BACKEND_PATH

configurations:
  env:
    - name: LOG_LEVEL
      value: info
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secrets
          key: password
  files:
    - name: config.json
      mountPath: /etc/config/config.json
      value: |
        {"debug": false}
```

The descriptor and the Workload CR both use `name`/`key` plus `valueFrom.secretKeyRef`. The build workflow merges the built image into the descriptor to produce the Workload CR.

> **The descriptor's `metadata.name` is read but ignored.** The build always names the generated Workload `{component}-workload`, regardless of what's in `workload.yaml`. So a Component named `api-service` produces a Workload named `api-service-workload`. Query the workload by that name (e.g. `occ workload get api-service-workload`), not by the component name.

## Environment

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Environment
metadata:
  name: development
  namespace: default
  labels:
    openchoreo.dev/name: development
spec:
  dataPlaneRef:
    kind: DataPlane
    name: default
  isProduction: false
```

## DeploymentPipeline

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: DeploymentPipeline
metadata:
  name: default-pipeline
  namespace: default
spec:
  promotionPaths:
    - sourceEnvironmentRef:
        name: development             # `kind: Environment` is implicit
      targetEnvironmentRefs:
        - name: staging
    - sourceEnvironmentRef:
        name: staging
      targetEnvironmentRefs:
        - name: production
```

> **Important**: `sourceEnvironmentRef` is an **object** (`{name: <env>}`), not a plain string — same shape as `targetEnvironmentRefs[]`. `kind` defaults to `Environment` and is usually omitted.

## ReleaseBinding

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ReleaseBinding
metadata:
  name: my-app-development
  namespace: default
spec:
  environment: development
  owner:
    componentName: my-app
    projectName: my-project
  releaseName: my-app-20260301-1
  state: Active
  componentTypeEnvironmentConfigs:
    replicas: 3
  traitEnvironmentConfigs:
    storage:
      size: 100Gi
      storageClass: fast-ssd
  workloadOverrides:
    container:
      env:
        - key: LOG_LEVEL
          value: debug
```

**Notes**:
- `ReleaseBinding` is usually created by `occ component deploy`; hand-write it only when you need explicit overrides.
- Current `state` values used by the CRD are `Active` and `Undeploy`.
- Deployed endpoint URLs appear in `status.endpoints[].invokeURL`, `externalURLs`, and `internalURLs`.

## SecretReference

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: SecretReference
metadata:
  name: db-secrets
  namespace: default
spec:
  template:
    type: Opaque
    metadata:
      labels:
        app: my-app
  data:
    - secretKey: password
      remoteRef:
        key: database/credentials
        property: password
  refreshInterval: 1h
```

## ComponentType (read-only for developers)

Simplified shape for understanding what platform engineers configure. Developers pick types from `occ clustercomponenttype list`. For full authoring detail (schema, templates, patches, validation), see `openchoreo-platform-engineer/references/component-types-and-traits.md`.

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ComponentType               # or ClusterComponentType
metadata:
  name: web-service
  namespace: default              # omit for ClusterComponentType
spec:
  workloadType: deployment        # deployment | statefulset | cronjob | job | proxy
  allowedTraits:
    - kind: Trait                 # or ClusterTrait
      name: persistent-volume
  allowedWorkflows:
    - kind: ClusterWorkflow
      name: dockerfile-builder
  parameters:
    openAPIV3Schema:
      type: object
      properties:
        replicas:
          type: integer
          default: 1
          minimum: 1
  environmentConfigs:
    openAPIV3Schema:
      type: object
      properties:
        resources:
          type: object
          default: {}
          properties:
            cpu:    { type: string, default: "100m" }
            memory: { type: string, default: "256Mi" }
  resources:
    - id: deployment              # must match workloadType
      template:
        apiVersion: apps/v1
        kind: Deployment
        # ... CEL-templated Kubernetes resource
```

## Trait (read-only for developers)

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Trait                       # or ClusterTrait
metadata:
  name: persistent-volume
  namespace: default              # omit for ClusterTrait
spec:
  parameters:
    openAPIV3Schema:
      type: object
      properties:
        volumeName: { type: string }
        mountPath:  { type: string }
        containerName:
          type: string
          default: main
  environmentConfigs:
    openAPIV3Schema:
      type: object
      properties:
        size:
          type: string
          default: "10Gi"
        storageClass:
          type: string
          default: "standard"
  creates:
    - template:
        apiVersion: v1
        kind: PersistentVolumeClaim
        # ... CEL-templated resource
  patches:
    - target:
        kind: Deployment
        group: apps
        version: v1
      operations:
        - op: add
          path: /spec/template/spec/volumes/-
          value:
            name: ${parameters.volumeName}
```

Both ComponentType and Trait use OpenAPI v3 JSON Schema under `parameters.openAPIV3Schema` and `environmentConfigs.openAPIV3Schema`.
