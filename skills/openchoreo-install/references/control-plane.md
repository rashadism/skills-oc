# Control Plane Installation

## Step 1 — Create self-signed CA

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-bootstrap
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openchoreo-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: openchoreo-ca
  secretName: openchoreo-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-bootstrap
    kind: ClusterIssuer
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: openchoreo-ca
spec:
  ca:
    secretName: openchoreo-ca-secret
EOF

kubectl wait --for=condition=Ready certificate/openchoreo-ca \
  -n cert-manager --timeout=60s
```

> **Production TLS:** Replace `openchoreo-ca` ClusterIssuer with Let's Encrypt or your corporate CA. All Certificate resources reference this issuer — it is a single swap.

## Step 2 — Initial control plane install (placeholder hostnames)

```bash
helm upgrade --install openchoreo-control-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane \
  --version 1.0.0 \
  --namespace openchoreo-control-plane \
  --create-namespace \
  --values - <<'EOF'
openchoreoApi:
  http:
    hostnames:
      - "api.placeholder.tld"
backstage:
  baseUrl: "https://console.placeholder.tld"
  secretName: backstage-secrets
  http:
    hostnames:
      - "console.placeholder.tld"
security:
  oidc:
    issuer: "https://thunder.placeholder.tld"
gateway:
  tls:
    enabled: false
EOF
```

## Step 3 — Resolve LoadBalancer IP and set domain

**EKS only** — patch to internet-facing before waiting:
```bash
kubectl patch svc gateway-default -n openchoreo-control-plane \
  -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-scheme":"internet-facing"}}}'
```

Wait for address:
```bash
kubectl get svc gateway-default -n openchoreo-control-plane -w
```

Resolve IP and derive domain (works for both IP and hostname-based LBs):
```bash
CP_LB_IP=$(kubectl get svc gateway-default -n openchoreo-control-plane \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$CP_LB_IP" ]; then
  CP_LB_HOSTNAME=$(kubectl get svc gateway-default -n openchoreo-control-plane \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  CP_LB_IP=$(dig +short "$CP_LB_HOSTNAME" | head -1)
fi
export CP_BASE_DOMAIN="openchoreo.${CP_LB_IP//./-}.nip.io"
echo "Control plane domain: ${CP_BASE_DOMAIN}"
```

## Step 4 — Control plane TLS certificate

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cp-gateway-tls
  namespace: openchoreo-control-plane
spec:
  secretName: cp-gateway-tls
  issuerRef:
    name: openchoreo-ca
    kind: ClusterIssuer
  dnsNames:
    - "*.${CP_BASE_DOMAIN}"
    - "${CP_BASE_DOMAIN}"
  privateKey:
    rotationPolicy: Always
EOF

kubectl wait --for=condition=Ready certificate/cp-gateway-tls \
  -n openchoreo-control-plane --timeout=60s
```

## Step 5 — Install Thunder (identity provider, v0.26.0)

```bash
curl -fsSL https://raw.githubusercontent.com/openchoreo/openchoreo/refs/tags/v1.0.0/install/k3d/common/values-thunder.yaml \
| sed "s#http://thunder.openchoreo.localhost:8080#https://thunder.${CP_BASE_DOMAIN}#g" \
| sed "s#thunder.openchoreo.localhost#thunder.${CP_BASE_DOMAIN}#g" \
| sed "s#http://openchoreo.localhost:8080#https://console.${CP_BASE_DOMAIN}#g" \
| sed "s#port: 8080#port: 443#g" \
| sed 's#scheme: "http"#scheme: "https"#g' \
| helm upgrade --install thunder oci://ghcr.io/asgardeo/helm-charts/thunder \
  --namespace thunder \
  --create-namespace \
  --version 0.26.0 \
  --values -

kubectl wait -n thunder \
  --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=thunder
```

Thunder admin console: `https://thunder.${CP_BASE_DOMAIN}/develop`
- Username: `admin` / Password: `admin`

> **Gotcha:** Thunder configuration is stored in a PVC. If you need to change OIDC settings, you must delete the PVC and reinstall — `helm upgrade` alone will not apply config changes.

## Step 6 — Backstage secrets

```bash
kubectl apply -f - <<EOF
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
```

## Step 7 — Reconfigure control plane with real hostnames

```bash
helm upgrade openchoreo-control-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane \
  --version 1.0.0 \
  --namespace openchoreo-control-plane \
  --reuse-values \
  --values - <<EOF
openchoreoApi:
  config:
    server:
      publicUrl: "https://api.${CP_BASE_DOMAIN}"
    security:
      authentication:
        jwt:
          jwks:
            skip_tls_verify: true
  http:
    hostnames:
      - "api.${CP_BASE_DOMAIN}"
backstage:
  secretName: backstage-secrets
  baseUrl: "https://console.${CP_BASE_DOMAIN}"
  http:
    hostnames:
      - "console.${CP_BASE_DOMAIN}"
  auth:
    redirectUrls:
      - "https://console.${CP_BASE_DOMAIN}/api/auth/openchoreo-auth/handler/frame"
  extraEnv:
    - name: NODE_TLS_REJECT_UNAUTHORIZED
      value: "0"
security:
  oidc:
    issuer: "https://thunder.${CP_BASE_DOMAIN}"
    jwksUrl: "https://thunder.${CP_BASE_DOMAIN}/oauth2/jwks"
    authorizationUrl: "https://thunder.${CP_BASE_DOMAIN}/oauth2/authorize"
    tokenUrl: "https://thunder.${CP_BASE_DOMAIN}/oauth2/token"
gateway:
  tls:
    enabled: true
    hostname: "*.${CP_BASE_DOMAIN}"
    certificateRefs:
      - name: cp-gateway-tls
EOF
```

Update Thunder HTTPRoute:
```bash
helm upgrade thunder oci://ghcr.io/asgardeo/helm-charts/thunder \
  --namespace thunder \
  --version 0.26.0 \
  --reuse-values \
  --set "httproute.hostnames[0]=thunder.${CP_BASE_DOMAIN}"
```

Wait for all deployments:
```bash
kubectl wait -n openchoreo-control-plane \
  --for=condition=available --timeout=300s deployment --all

kubectl wait -n openchoreo-control-plane \
  --for=condition=Ready certificate/cluster-gateway-ca --timeout=120s
```

## Step 8 — Verify control plane

```bash
curl -sk https://thunder.${CP_BASE_DOMAIN}/health/readiness
curl -sk https://api.${CP_BASE_DOMAIN}/health
curl -sk -o /dev/null -w "%{http_code}" https://console.${CP_BASE_DOMAIN}/
```

All should return 200.

Console URL: `https://console.${CP_BASE_DOMAIN}`
- Username: `admin@openchoreo.dev`
- Password: `Admin@123`

## Step 9 — Install default resources

```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/refs/tags/v1.0.0/samples/getting-started/all.yaml

kubectl label namespace default openchoreo.dev/control-plane=true
```

This installs the default namespace, environments, deployment pipeline, ComponentTypes, Traits, and ClusterWorkflows.
