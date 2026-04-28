# Cleanup / Uninstall

Run in this order — remove registrations before uninstalling planes.

## Step 1 — Delete plane registrations

```bash
kubectl delete clusterdataplane default 2>/dev/null || true
kubectl delete clusterworkflowplane default 2>/dev/null || true
kubectl delete clusterobservabilityplane default 2>/dev/null || true
```

## Step 2 — Uninstall planes

```bash
helm uninstall openchoreo-observability-plane -n openchoreo-observability-plane 2>/dev/null || true
helm uninstall observability-logs-opensearch   -n openchoreo-observability-plane 2>/dev/null || true
helm uninstall observability-metrics-prometheus -n openchoreo-observability-plane 2>/dev/null || true
helm uninstall observability-traces-opensearch  -n openchoreo-observability-plane 2>/dev/null || true

helm uninstall openchoreo-workflow-plane -n openchoreo-workflow-plane 2>/dev/null || true

helm uninstall openchoreo-data-plane -n openchoreo-data-plane 2>/dev/null || true

helm uninstall openchoreo-control-plane -n openchoreo-control-plane 2>/dev/null || true
helm uninstall thunder -n thunder 2>/dev/null || true
helm uninstall kgateway -n openchoreo-control-plane 2>/dev/null || true
helm uninstall kgateway-crds -n openchoreo-control-plane 2>/dev/null || true
```

## Step 3 — Uninstall shared prerequisites

```bash
helm uninstall openbao          -n openbao           2>/dev/null || true
helm uninstall external-secrets -n external-secrets  2>/dev/null || true
helm uninstall cert-manager     -n cert-manager      2>/dev/null || true
```

## Step 4 — Delete namespaces

```bash
kubectl delete namespace \
  openchoreo-control-plane \
  thunder \
  openchoreo-data-plane \
  openchoreo-workflow-plane \
  openchoreo-observability-plane \
  external-secrets \
  openbao \
  cert-manager \
  2>/dev/null || true
```

## Step 5 — Remove Gateway API CRDs (optional)

Only do this if no other workloads in the cluster use Gateway API:

```bash
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml \
  2>/dev/null || true
```

## Step 6 — Remove default namespace label

```bash
kubectl label namespace default openchoreo.dev/control-plane-
```
