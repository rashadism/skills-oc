# Workflow Plane Installation

The workflow plane provides source-build capabilities using Argo Workflows. It is optional — skip if you only need BYO-image (pre-built) deployments.

> **Prerequisite:** Control plane and data plane must be installed first.

## Step 1 — Create namespace and copy CA

```bash
kubectl create namespace openchoreo-workflow-plane --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret cluster-gateway-ca -n openchoreo-control-plane \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | \
  kubectl create configmap cluster-gateway-ca \
    --from-file=ca.crt=/dev/stdin \
    -n openchoreo-workflow-plane \
    --dry-run=client -o yaml | kubectl apply -f -
```

## Step 2 — Install workflow plane

```bash
helm upgrade --install openchoreo-workflow-plane oci://ghcr.io/openchoreo/helm-charts/openchoreo-workflow-plane \
  --version 1.0.0 \
  --namespace openchoreo-workflow-plane \
  --create-namespace \
  --set clusterAgent.tls.generateCerts=true
```

## Step 3 — Install workflow templates

Checkout step (clones source repo):
```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/getting-started/workflow-templates/checkout-source.yaml
```

Build coordinator and generate-workload step:
```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/getting-started/workflow-templates.yaml
```

Publish step (pushes image to registry):
```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/getting-started/workflow-templates/publish-image.yaml
```

> **Default image registry:** The publish template uses [ttl.sh](https://ttl.sh) — a free ephemeral registry. Images expire after **24 hours**. For production, replace with a real registry (ECR, GCR, Docker Hub) and configure registry credentials on the workflow plane.

## Step 4 — Register ClusterWorkflowPlane

```bash
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

## Step 5 — Verify workflow plane

Deploy a Go service from source:
```bash
kubectl apply -f https://raw.githubusercontent.com/openchoreo/openchoreo/main/samples/from-source/services/go-docker-greeter/greeting-service.yaml

kubectl get workflow -n workflows-default --watch
```

Wait for the build and deployment:
```bash
kubectl wait --for=condition=available deployment \
  -l openchoreo.dev/component=greeting-service -A --timeout=300s
```

Get the URL:
```bash
HOSTNAME=$(kubectl get httproute -A -l openchoreo.dev/component=greeting-service \
  -o jsonpath='{.items[0].spec.hostnames[0]}')
PATH_PREFIX=$(kubectl get httproute -A -l openchoreo.dev/component=greeting-service \
  -o jsonpath='{.items[0].spec.rules[0].matches[0].path.value}')
DP_HTTPS_PORT=$(kubectl get gateway gateway-default -n openchoreo-data-plane \
  -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].port}')
PORT_SUFFIX=$([ "$DP_HTTPS_PORT" = "443" ] && echo "" || echo ":${DP_HTTPS_PORT}")
curl -k "https://${HOSTNAME}${PORT_SUFFIX}${PATH_PREFIX}/greeter/greet"
```

## Known issues

**k3s / Rancher Desktop — cgroup controller error:**
```
crun: requested cgroup controller 'pids' is not available
```
This occurs because Docker doesn't delegate all cgroup v2 controllers. Switch to the `containerd` runtime to resolve it.
