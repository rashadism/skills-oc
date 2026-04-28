# Prerequisites

## Tool requirements

| Tool | Minimum version | Purpose |
|---|---|---|
| `kubectl` | v1.32+ | Kubernetes CLI |
| `helm` | v3.12+ | Package manager |

Verify:
```bash
kubectl version --client
helm version --short
kubectl get nodes
kubectl auth can-i '*' '*' --all-namespaces
```

## Cluster requirements

- Kubernetes 1.32+
- LoadBalancer support (cloud provider or MetalLB for bare metal)
- Default StorageClass

## Step 1 — Gateway API CRDs

```bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml
```

## Step 2 — cert-manager (v1.19.2)

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.19.2 \
  --set crds.enabled=true \
  --wait --timeout 180s
```

## Step 3 — External Secrets Operator (v1.3.2)

```bash
helm upgrade --install external-secrets oci://ghcr.io/external-secrets/charts/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version 1.3.2 \
  --set installCRDs=true \
  --wait --timeout 180s
```

## Step 4 — kgateway (v2.2.1)

Install CRDs first:
```bash
helm upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --create-namespace --namespace openchoreo-control-plane \
  --version v2.2.1
```

Then install kgateway:
```bash
helm upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace openchoreo-control-plane --create-namespace \
  --version v2.2.1 \
  --set controller.extraEnv.KGW_ENABLE_GATEWAY_API_EXPERIMENTAL_FEATURES=true
```

## Step 5 — OpenBao (secret backend, v0.25.6)

```bash
helm upgrade --install openbao oci://ghcr.io/openbao/charts/openbao \
  --namespace openbao \
  --create-namespace \
  --version 0.25.6 \
  --values https://raw.githubusercontent.com/openchoreo/openchoreo/main/install/k3d/common/values-openbao.yaml \
  --wait --timeout 300s
```

> **Production:** Set `server.dev.enabled=false` and configure proper storage and unsealing. The default install uses dev mode (in-memory, no persistence).

The install seeds these secrets into OpenBao:

| Secret key | Value |
|---|---|
| `backstage-backend-secret` | `local-dev-backend-secret` |
| `backstage-client-secret` | `backstage-portal-secret` |
| `opensearch-username` | `admin` |
| `opensearch-password` | `ThisIsTheOpenSearchPassword1` |

## Step 6 — ClusterSecretStore

Connects External Secrets Operator to OpenBao:

```bash
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
```
