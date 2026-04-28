# Data Plane Installation

> **Prerequisite:** Control plane must be fully installed and `cluster-gateway-ca` certificate must be Ready before proceeding.

## Step 1 — Create namespace and copy CA

```bash
kubectl create namespace openchoreo-data-plane --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret cluster-gateway-ca -n openchoreo-control-plane \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | \
  kubectl create configmap cluster-gateway-ca \
    --from-file=ca.crt=/dev/stdin \
    -n openchoreo-data-plane \
    --dry-run=client -o yaml | kubectl apply -f -
```

## Step 2 — Install data plane (TLS disabled initially)

```bash
helm upgrade --install openchoreo-data-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane \
  --version 1.0.0 \
  --namespace openchoreo-data-plane \
  --create-namespace \
  --set gateway.tls.enabled=false
```

> **Single-node clusters** (k3s, Rancher Desktop, kind): add port offsets to avoid conflict with the control plane gateway:
> ```
> --set gateway.httpPort=8080 --set gateway.httpsPort=8443
> ```

## Step 3 — Resolve LoadBalancer IP and set domain

**EKS only** — patch to internet-facing:
```bash
kubectl patch svc gateway-default -n openchoreo-data-plane \
  -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-scheme":"internet-facing"}}}'
```

Wait for address:
```bash
kubectl get svc gateway-default -n openchoreo-data-plane -w
```

Resolve IP:
```bash
DP_LB_IP=$(kubectl get svc gateway-default -n openchoreo-data-plane \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$DP_LB_IP" ]; then
  DP_LB_HOSTNAME=$(kubectl get svc gateway-default -n openchoreo-data-plane \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  DP_LB_IP=$(dig +short "$DP_LB_HOSTNAME" | head -1)
fi
export DP_DOMAIN="apps.openchoreo.${DP_LB_IP//./-}.nip.io"
echo "Data plane domain: ${DP_DOMAIN}"
```

## Step 4 — TLS certificate

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dp-gateway-tls
  namespace: openchoreo-data-plane
spec:
  secretName: dp-gateway-tls
  issuerRef:
    name: openchoreo-ca
    kind: ClusterIssuer
  dnsNames:
    - "*.${DP_DOMAIN}"
    - "${DP_DOMAIN}"
  privateKey:
    rotationPolicy: Always
EOF

kubectl wait --for=condition=Ready certificate/dp-gateway-tls \
  -n openchoreo-data-plane --timeout=60s
```

## Step 5 — Enable TLS

```bash
helm upgrade openchoreo-data-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane \
  --version 1.0.0 \
  --namespace openchoreo-data-plane \
  --reuse-values \
  --values - <<EOF
gateway:
  tls:
    enabled: true
    hostname: "*.${DP_DOMAIN}"
    certificateRefs:
      - name: dp-gateway-tls
EOF
```

## Step 6 — Register ClusterDataPlane

```bash
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
          host: ${DP_DOMAIN}
          listenerName: http
          port: 80
        name: gateway-default
        namespace: openchoreo-data-plane
EOF
```

## Step 7 — Verify data plane

Deploy the sample React app:
```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/from-image/react-starter-web-app/react-starter.yaml

kubectl wait --for=condition=available deployment \
  -l openchoreo.dev/component=react-starter -A --timeout=180s
```

Get the URL:
```bash
HOSTNAME=$(kubectl get httproute -A -l openchoreo.dev/component=react-starter \
  -o jsonpath='{.items[0].spec.hostnames[0]}')
DP_HTTPS_PORT=$(kubectl get gateway gateway-default -n openchoreo-data-plane \
  -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].port}')
PORT_SUFFIX=$([ "$DP_HTTPS_PORT" = "443" ] && echo "" || echo ":${DP_HTTPS_PORT}")
echo "https://${HOSTNAME}${PORT_SUFFIX}"
```

Open the URL in a browser — you should see the React starter app.
