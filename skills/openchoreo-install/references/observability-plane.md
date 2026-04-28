# Observability Plane Installation

The observability plane provides logs (OpenSearch), metrics (Prometheus), and traces (OpenSearch). It is optional.

> **Prerequisite:** Control plane, data plane, and workflow plane must be installed first.

## Step 1 — Create namespace and copy CA

```bash
kubectl create namespace openchoreo-observability-plane --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret cluster-gateway-ca -n openchoreo-control-plane \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | \
  kubectl create configmap cluster-gateway-ca \
    --from-file=ca.crt=/dev/stdin \
    -n openchoreo-observability-plane \
    --dry-run=client -o yaml | kubectl apply -f -
```

## Step 2 — Create observability secrets

```bash
kubectl apply -f - <<EOF
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
```

## Step 3 — Install observability plane core (TLS disabled initially)

```bash
helm upgrade --install openchoreo-observability-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-observability-plane \
  --version 1.0.0 \
  --namespace openchoreo-observability-plane \
  --create-namespace \
  --timeout 25m \
  --values - <<EOF
observer:
  openSearchSecretName: opensearch-admin-credentials
  secretName: observer-secret
gateway:
  tls:
    enabled: false
EOF
```

> **Single-node clusters:** add `--set gateway.httpPort=9080 --set gateway.httpsPort=9443` to avoid port conflicts.

## Step 4 — Install observability modules

### Logs (OpenSearch)
```bash
helm upgrade --install observability-logs-opensearch \
  oci://ghcr.io/openchoreo/helm-charts/observability-logs-opensearch \
  --create-namespace \
  --namespace openchoreo-observability-plane \
  --version 0.3.8 \
  --set openSearchSetup.openSearchSecretName="opensearch-admin-credentials"
```

### Metrics (Prometheus)
```bash
helm upgrade --install observability-metrics-prometheus \
  oci://ghcr.io/openchoreo/helm-charts/observability-metrics-prometheus \
  --create-namespace \
  --namespace openchoreo-observability-plane \
  --version 0.2.4
```

### Traces (OpenSearch)
```bash
helm upgrade --install observability-traces-opensearch \
  oci://ghcr.io/openchoreo/helm-charts/observability-tracing-opensearch \
  --create-namespace \
  --namespace openchoreo-observability-plane \
  --version 0.3.7 \
  --set openSearch.enabled=false \
  --set openSearchSetup.openSearchSecretName="opensearch-admin-credentials"
```

## Step 5 — Resolve LoadBalancer IP and set domain

```bash
OBS_LB_IP=$(kubectl get svc gateway-default -n openchoreo-observability-plane \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$OBS_LB_IP" ]; then
  OBS_LB_HOSTNAME=$(kubectl get svc gateway-default -n openchoreo-observability-plane \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  OBS_LB_IP=$(dig +short "$OBS_LB_HOSTNAME" | head -1)
fi
export OBS_BASE_DOMAIN="openchoreo.observability.${OBS_LB_IP//./-}.nip.io"
export OBS_DOMAIN="observer.${OBS_BASE_DOMAIN}"
echo "Observability domain: ${OBS_DOMAIN}"
```

## Step 6 — TLS certificate

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: obs-gateway-tls
  namespace: openchoreo-observability-plane
spec:
  secretName: obs-gateway-tls
  issuerRef:
    name: openchoreo-ca
    kind: ClusterIssuer
  dnsNames:
    - "*.${OBS_BASE_DOMAIN}"
    - "${OBS_DOMAIN}"
  privateKey:
    rotationPolicy: Always
EOF

kubectl wait --for=condition=Ready certificate/obs-gateway-tls \
  -n openchoreo-observability-plane --timeout=60s
```

## Step 7 — Configure observability plane with real hostnames

```bash
helm upgrade openchoreo-observability-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-observability-plane \
  --version 1.0.0 \
  --namespace openchoreo-observability-plane \
  --reuse-values \
  --timeout 10m \
  --values - <<EOF
observer:
  openSearchSecretName: opensearch-admin-credentials
  secretName: observer-secret
  controlPlaneApiUrl: "https://api.${CP_BASE_DOMAIN}"
  http:
    hostnames:
      - "observer.${OBS_BASE_DOMAIN}"
  cors:
    allowedOrigins:
      - "https://console.${CP_BASE_DOMAIN}"
  authzTlsInsecureSkipVerify: true
security:
  oidc:
    issuer: "https://thunder.${CP_BASE_DOMAIN}"
    jwksUrl: "https://thunder.${CP_BASE_DOMAIN}/oauth2/jwks"
    tokenUrl: "https://thunder.${CP_BASE_DOMAIN}/oauth2/token"
    jwksUrlTlsInsecureSkipVerify: "true"
    uidResolverTlsInsecureSkipVerify: "true"
gateway:
  tls:
    enabled: true
    hostname: "*.${OBS_BASE_DOMAIN}"
    certificateRefs:
      - name: obs-gateway-tls
EOF
```

## Step 8 — Register ClusterObservabilityPlane

```bash
AGENT_CA=$(kubectl get secret cluster-agent-tls \
  -n openchoreo-observability-plane -o jsonpath='{.data.ca\.crt}' | base64 -d)

OBS_HTTPS_PORT=$(kubectl get gateway gateway-default -n openchoreo-observability-plane \
  -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].port}')
OBS_PORT_SUFFIX=$([ "$OBS_HTTPS_PORT" = "443" ] && echo "" || echo ":${OBS_HTTPS_PORT}")

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
  observerURL: https://${OBS_DOMAIN}${OBS_PORT_SUFFIX}
EOF
```

## Step 9 — Link planes to observability

```bash
kubectl patch clusterdataplane default --type merge \
  -p '{"spec":{"observabilityPlaneRef":{"kind":"ClusterObservabilityPlane","name":"default"}}}'

kubectl patch clusterworkflowplane default --type merge \
  -p '{"spec":{"observabilityPlaneRef":{"kind":"ClusterObservabilityPlane","name":"default"}}}'
```

## Step 10 — Enable Fluent Bit log collection

```bash
helm upgrade -n openchoreo-observability-plane observability-logs-opensearch \
  oci://ghcr.io/openchoreo/helm-charts/observability-logs-opensearch \
  --version 0.3.8 \
  --reuse-values \
  --set fluent-bit.enabled=true
```

## Step 11 — Verify

```bash
OBS_HTTPS_PORT=$(kubectl get gateway gateway-default -n openchoreo-observability-plane \
  -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].port}')
OBS_PORT_SUFFIX=$([ "$OBS_HTTPS_PORT" = "443" ] && echo "" || echo ":${OBS_HTTPS_PORT}")
curl -sk "https://${OBS_DOMAIN}${OBS_PORT_SUFFIX}/health"
```

> **Note:** Your browser needs to separately accept the self-signed certificate for the observer domain. Navigate to the observer URL directly in the browser and accept the certificate before using the observability UI in the console.
