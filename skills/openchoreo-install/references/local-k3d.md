# Local Installation with k3d

Use this path for local development when you want guaranteed browser access via `localhost` ports. It uses fixed `*.openchoreo.localhost` domains with plain HTTP and pre-built values files — no TLS, no nip.io, no LoadBalancer IP resolution.

> **Recommended for:** Docker Desktop or any local machine with Docker, when Chrome browser access to the console is required.
>
> **Colima users:** prefer [local-colima.md](local-colima.md) instead — it uses Colima's native k3s with no extra tools.
>
> **Not recommended for:** production, shared clusters, or cloud environments — use `control-plane.md` + `data-plane.md` instead.

## Prerequisites

| Tool | Version |
|---|---|
| Docker | v26+ (allocate ≥ 8 GB RAM, ≥ 4 CPU to the VM) |
| k3d | v5.8+ |
| kubectl | v1.32+ |
| Helm | v3.12+ |

```bash
docker --version && k3d --version && kubectl version --client && helm version --short
```

Install k3d if needed:
```bash
brew install k3d      # macOS
# or
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

## Step 1 — Create the k3d cluster

```bash
curl -fsSL https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/config.yaml \
  | k3d cluster create --config=-
```

> **Colima users:** prefix with `K3D_FIX_DNS=0` to prevent DNS conflicts between Colima's internal resolver and k3d:
> ```bash
> K3D_FIX_DNS=0 k3d cluster create --config=- < <(curl -fsSL https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/config.yaml)
> ```

This creates a cluster named `openchoreo` with pre-mapped ports:
| Port (host) | Purpose |
|---|---|
| `8080` | Console + API + Thunder |
| `19080` | Data plane HTTP (deployed apps) |
| `10081` | Argo Workflows UI |
| `10082` | In-cluster Docker registry |
| `11080` | Observability Observer |

## Step 2 — Install prerequisites

Run all prerequisites in one shot:
```bash
curl -fsSL https://raw.githubusercontent.com/openchoreo/openchoreo/refs/tags/v1.0.0/install/k3d/single-cluster/install-prerequisites.sh | bash
```

Or manually (same result):

```bash
# Gateway API CRDs
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml

# cert-manager
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager --create-namespace --version v1.19.2 \
  --set crds.enabled=true --wait --timeout 180s

# External Secrets Operator
helm upgrade --install external-secrets oci://ghcr.io/external-secrets/charts/external-secrets \
  --namespace external-secrets --create-namespace --version 1.3.2 \
  --set installCRDs=true --wait --timeout 180s

# kgateway CRDs
helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --create-namespace --namespace openchoreo-control-plane --version v2.2.1

# kgateway controller
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace openchoreo-control-plane --create-namespace --version v2.2.1 \
  --set controller.extraEnv.KGW_ENABLE_GATEWAY_API_EXPERIMENTAL_FEATURES=true

# OpenBao (secret backend)
helm upgrade --install openbao oci://ghcr.io/openbao/charts/openbao \
  --namespace openbao --create-namespace --version 0.25.6 \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/common/values-openbao.yaml \
  --wait --timeout 300s

# ClusterSecretStore
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-openbao
  namespace: openbao
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: default
spec:
  provider:
    vault:
      server: "http://openbao.openbao.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "openchoreo-secret-writer-role"
          serviceAccountRef:
            name: "external-secrets-openbao"
            namespace: "openbao"
EOF

# CoreDNS rewrite (routes *.openchoreo.localhost inside the cluster)
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/common/coredns-custom.yaml
```

## Step 3 — Install control plane

```bash
# Thunder (identity provider)
helm upgrade --install thunder oci://ghcr.io/asgardeo/helm-charts/thunder \
  --namespace thunder --create-namespace --version 0.26.0 \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/refs/tags/v1.0.0/install/k3d/common/values-thunder.yaml

kubectl wait -n thunder --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=thunder

# Backstage secrets
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: backstage-secrets
  namespace: openchoreo-control-plane
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: default
  target:
    name: backstage-secrets
  data:
  - secretKey: backend-secret
    remoteRef:
      key: backstage-backend-secret
      property: value
  - secretKey: client-secret
    remoteRef:
      key: backstage-client-secret
      property: value
  - secretKey: jenkins-api-key
    remoteRef:
      key: backstage-jenkins-api-key
      property: value
EOF

# Control plane
helm upgrade --install openchoreo-control-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane \
  --version 1.0.0 --namespace openchoreo-control-plane --create-namespace \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/values-cp.yaml

kubectl wait -n openchoreo-control-plane --for=condition=available --timeout=300s deployment --all
```

Console: **http://openchoreo.localhost:8080** — `admin@openchoreo.dev` / `Admin@123`

Thunder admin: http://thunder.openchoreo.localhost:8080/develop — `admin` / `admin`

## Step 4 — Install default resources

```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/refs/tags/v1.0.0/samples/getting-started/all.yaml
kubectl label namespace default openchoreo.dev/control-plane=true
```

## Step 5 — Install data plane

```bash
kubectl create namespace openchoreo-data-plane --dry-run=client -o yaml | kubectl apply -f -

kubectl wait -n openchoreo-control-plane \
  --for=condition=Ready certificate/cluster-gateway-ca --timeout=120s

CA_CRT=$(kubectl get secret cluster-gateway-ca \
  -n openchoreo-control-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)
kubectl create configmap cluster-gateway-ca \
  --from-literal=ca.crt="$CA_CRT" \
  -n openchoreo-data-plane --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install openchoreo-data-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane \
  --version 1.0.0 --namespace openchoreo-data-plane --create-namespace \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/values-dp.yaml

AGENT_CA=$(kubectl get secret cluster-agent-tls \
  -n openchoreo-data-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)

kubectl apply -f - <<EOF
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterDataPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
$(echo "$AGENT_CA" | sed 's/^/        /')
  secretStoreRef:
    name: default
  gateway:
    ingress:
      external:
        http:
          host: openchoreoapis.localhost
          listenerName: http
          port: 19080
        name: gateway-default
        namespace: openchoreo-data-plane
EOF
```

## Step 6 — Install workflow plane (optional)

Required for source builds (`dockerfile-builder`). Skip if you only need BYO-image deployments.

```bash
kubectl create namespace openchoreo-workflow-plane --dry-run=client -o yaml | kubectl apply -f -

CA_CRT=$(kubectl get secret cluster-gateway-ca \
  -n openchoreo-control-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)
kubectl create configmap cluster-gateway-ca \
  --from-literal=ca.crt="$CA_CRT" \
  -n openchoreo-workflow-plane --dry-run=client -o yaml | kubectl apply -f -

# In-cluster Docker registry (builds push here instead of ttl.sh)
helm repo add twuni https://twuni.github.io/docker-registry.helm && helm repo update
helm install registry twuni/docker-registry \
  --namespace openchoreo-workflow-plane --create-namespace \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/values-registry.yaml

# Workflow plane
helm upgrade --install openchoreo-workflow-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-workflow-plane \
  --version 1.0.0 --namespace openchoreo-workflow-plane \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/values-wp.yaml

# Workflow templates (use publish-image-k3d.yaml — pushes to local registry, not ttl.sh)
kubectl apply \
  -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/getting-started/workflow-templates/checkout-source.yaml \
  -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/getting-started/workflow-templates.yaml \
  -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/getting-started/workflow-templates/publish-image-k3d.yaml

AGENT_CA=$(kubectl get secret cluster-agent-tls \
  -n openchoreo-workflow-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)

kubectl apply -f - <<EOF
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterWorkflowPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
$(echo "$AGENT_CA" | sed 's/^/        /')
  secretStoreRef:
    name: default
EOF
```

Argo Workflows UI: http://localhost:10081

## Step 7 — Install observability plane (optional)

```bash
kubectl create namespace openchoreo-observability-plane --dry-run=client -o yaml | kubectl apply -f -

CA_CRT=$(kubectl get secret cluster-gateway-ca \
  -n openchoreo-control-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)
kubectl create configmap cluster-gateway-ca \
  --from-literal=ca.crt="$CA_CRT" \
  -n openchoreo-observability-plane --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: opensearch-admin-credentials
  namespace: openchoreo-observability-plane
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: default
  target:
    name: opensearch-admin-credentials
  data:
  - secretKey: username
    remoteRef:
      key: opensearch-username
      property: value
  - secretKey: password
    remoteRef:
      key: opensearch-password
      property: value
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: observer-secret
  namespace: openchoreo-observability-plane
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: default
  target:
    name: observer-secret
  data:
  - secretKey: OPENSEARCH_USERNAME
    remoteRef:
      key: opensearch-username
      property: value
  - secretKey: OPENSEARCH_PASSWORD
    remoteRef:
      key: opensearch-password
      property: value
  - secretKey: UID_RESOLVER_OAUTH_CLIENT_SECRET
    remoteRef:
      key: observer-oauth-client-secret
      property: value
EOF

kubectl wait -n openchoreo-observability-plane \
  --for=condition=Ready externalsecret/opensearch-admin-credentials \
  externalsecret/observer-secret --timeout=60s

# Generate machine-id (required by OpenSearch)
docker exec k3d-openchoreo-server-0 sh -c \
  "cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id"

# Core observability plane
helm upgrade --install openchoreo-observability-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-observability-plane \
  --version 1.0.0 --namespace openchoreo-observability-plane \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/single-cluster/values-op.yaml \
  --timeout 25m

# Modules
helm upgrade --install observability-logs-opensearch \
  oci://ghcr.io/openchoreo/helm-charts/observability-logs-opensearch \
  --namespace openchoreo-observability-plane --version 0.3.8 \
  --set openSearchSetup.openSearchSecretName="opensearch-admin-credentials"

helm upgrade --install observability-traces-opensearch \
  oci://ghcr.io/openchoreo/helm-charts/observability-tracing-opensearch \
  --namespace openchoreo-observability-plane --version 0.3.7 \
  --set openSearch.enabled=false \
  --set openSearchSetup.openSearchSecretName="opensearch-admin-credentials"

helm upgrade --install observability-metrics-prometheus \
  oci://ghcr.io/openchoreo/helm-charts/observability-metrics-prometheus \
  --namespace openchoreo-observability-plane --version 0.2.4

# Enable Fluent Bit log collection
helm upgrade observability-logs-opensearch \
  oci://ghcr.io/openchoreo/helm-charts/observability-logs-opensearch \
  --namespace openchoreo-observability-plane --version 0.3.8 --reuse-values \
  --set fluent-bit.enabled=true

# Register
AGENT_CA=$(kubectl get secret cluster-agent-tls \
  -n openchoreo-observability-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)

kubectl apply -f - <<EOF
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterObservabilityPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
$(echo "$AGENT_CA" | sed 's/^/        /')
  observerURL: http://observer.openchoreo.localhost:11080
EOF

# Link planes to observability
kubectl patch clusterdataplane default --type merge \
  -p '{"spec":{"observabilityPlaneRef":{"kind":"ClusterObservabilityPlane","name":"default"}}}'

kubectl patch clusterworkflowplane default --type merge \
  -p '{"spec":{"observabilityPlaneRef":{"kind":"ClusterObservabilityPlane","name":"default"}}}'
```

## Access URLs (all via localhost)

| Service | URL |
|---|---|
| Console | http://openchoreo.localhost:8080 |
| API | http://api.openchoreo.localhost:8080 |
| Thunder (IdP admin) | http://thunder.openchoreo.localhost:8080/develop |
| Deployed apps | http://openchoreoapis.localhost:19080 |
| Argo Workflows UI | http://localhost:10081 |
| Observer | http://observer.openchoreo.localhost:11080 |

**Login:** `admin@openchoreo.dev` / `Admin@123`

No TLS, no certificate warnings, no hosts file changes needed.

## Verify

Deploy the sample React app:
```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/from-image/react-starter-web-app/react-starter.yaml

kubectl wait --for=condition=available deployment \
  -l openchoreo.dev/component=react-starter -A --timeout=120s

HOSTNAME=$(kubectl get httproute -A -l openchoreo.dev/component=react-starter \
  -o jsonpath='{.items[0].spec.hostnames[0]}')
echo "App URL: http://${HOSTNAME}:19080"
```

## Cleanup

```bash
k3d cluster delete openchoreo
```

## Colima-specific notes

- **Always prefix `k3d cluster create` with `K3D_FIX_DNS=0`** — Colima's internal DNS resolver conflicts with k3d's DNS injection without this flag
- **Docker runtime required** — Colima must be running with the `docker` runtime (not `containerd` only); the k3d cluster runs as Docker containers inside the VM
- **Port forwarding is automatic** — k3d maps container ports to `127.0.0.1` on the host, so all `localhost:XXXX` URLs work in the browser without any hosts file or port-forward setup
- **No bridge network issue** — unlike the native k3s approach (Colima's built-in k3s), k3d ports are properly forwarded to `localhost` and accessible from the browser immediately
- **Resource requirements** — set Colima to at least 8 GB RAM and 4 CPUs before creating the cluster: `colima stop && colima start --cpu 4 --memory 8`
