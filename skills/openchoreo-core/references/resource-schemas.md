# OpenChoreo Resource Schemas

All resources use `apiVersion: openchoreo.dev/v1alpha1`.

Prefer `occ component scaffold` or a matching sample from `samples/` before hand-writing YAML. Inspect the live cluster schema with the relevant MCP tool (`get_cluster_component_type_schema`, `get_workload_schema`, etc.) when unsure of a field shape.

This file holds **universal** resource schemas — those that any OpenChoreo workflow needs. PE-only schemas (DataPlane, WorkflowPlane, ObservabilityPlane, NotificationChannel) live in `openchoreo-platform-engineer/references/cli-platform.md`.

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
    kind: ComponentType
    name: deployment/service
  parameters: {}
  traits:
    - name: persistent-volume
      kind: Trait
      instanceName: storage
      parameters:
        volumeName: data
        mountPath: /var/data
  workflow:
    name: docker
    parameters:
      scope:
        projectName: "my-project"
        componentName: "my-app"
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
- Workflow names and parameter shapes come from the cluster. Use `occ workflow list` and `occ workflow get <name>`, or a matching sample from `samples/from-source/`.
- `componentType.name` is always `{workloadType}/{typeName}`.
- `repository.appPath` selects the service subdirectory and `workload.yaml`. `docker.context` and `docker.filePath` must still point at real repo-root-relative Docker build paths.
- Keep `spec.owner.projectName` and `spec.workflow.parameters.scope.projectName` aligned to the same target project before the first build. A mismatch can create Workloads under the wrong project owner.
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
      type: REST
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
    - component: backend-api
      endpoint: api
      visibility: project
      project: other-project
      envBindings:
        address: BACKEND_URL
        host: BACKEND_HOST
        port: BACKEND_PORT
        basePath: BACKEND_PATH
```

Every endpoint implicitly has `project` visibility. The `visibility` array adds `namespace`, `internal`, or `external`.

For reverse proxies, prefer `host` and `port` bindings unless you explicitly want the endpoint `basePath` included in the upstream URL.

## Workload Descriptor (`workload.yaml`)

Used for source builds. Place at the root of the `appPath` directory.

```yaml
apiVersion: openchoreo.dev/v1alpha1

metadata:
  name: my-service

endpoints:
  - name: api
    port: 8080
    type: REST
    targetPort: 8080
    displayName: "REST API"
    basePath: "/api/v1"
    schemaFile: openapi.yaml        # relative path, content is inlined by build
    visibility:
      - external

dependencies:
  - component: backend-api
    endpoint: api
    visibility: project
    project: other-project
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
    - sourceEnvironmentRef: development
      targetEnvironmentRefs:
        - name: staging
    - sourceEnvironmentRef: staging
      targetEnvironmentRefs:
        - name: production
```

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
  componentTypeEnvOverrides:
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

Included for understanding what platform engineers configure. Developers pick types from `occ clustercomponenttype list`. For full authoring detail, see `openchoreo-platform-engineer/references/templates-and-workflows.md`.

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ComponentType               # or ClusterComponentType
metadata:
  name: service
  namespace: default
spec:
  workloadType: deployment
  allowedWorkflows:
    - kind: Workflow
      name: docker
    - kind: Workflow
      name: google-cloud-buildpacks
  schema:
    parameters:
      replicas: "integer | default=1"
      imagePullPolicy: "string | enum=Always,IfNotPresent,Never | default=IfNotPresent"
    envOverrides:
      replicas: "integer | default=1 min=1 max=10"
      cpuLimit: "string | default=500m"
      memoryLimit: "string | default=256Mi"
  resources:
    - id: deployment
      template:
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: ${metadata.name}
          namespace: ${metadata.namespace}
        spec:
          replicas: ${envOverrides.replicas}
```

## Trait (read-only for developers)

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Trait                       # or ClusterTrait
metadata:
  name: persistent-volume
  namespace: default
spec:
  schema:
    parameters:
      volumeName: "string"
      mountPath: "string"
      containerName: "string | default=app"
    envOverrides:
      size: "string | default=10Gi"
      storageClass: "string | default=standard"
  creates:
    - template:
        apiVersion: v1
        kind: PersistentVolumeClaim
        # ... templates with CEL expressions
  patches:
    - target:
        group: apps
        version: v1
        kind: Deployment
      operations:
        - op: add
          path: /spec/template/spec/volumes/-
          value:
            name: ${parameters.volumeName}
```
