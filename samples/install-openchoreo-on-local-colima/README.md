# Sample: Install OpenChoreo on Local Colima

This sample shows how to use Claude Code with the `openchoreo-install` skill to perform a **fully automated, hands-off installation** of OpenChoreo on a local macOS machine using Colima's built-in k3s cluster.

A single prompt triggers the complete install: Colima startup, all prerequisites, control plane, data plane, workflow plane, and observability plane.

---

## What this sample covers

- Starting Colima with Kubernetes (k3s v1.33.4)
- Installing all prerequisites: Gateway API CRDs, cert-manager, External Secrets Operator, kgateway, OpenBao
- Installing the full OpenChoreo stack: control plane, data plane, workflow plane, observability plane
- Configuring `openchoreo.localhost` domains — Chrome-native secure context, no `/etc/hosts` needed
- Patching CoreDNS so in-cluster pods resolve `*.openchoreo.localhost` to the right gateway ClusterIPs
- Fixing the `NODE_ENV=development` Backstage auth issue automatically
- Registering `ClusterDataPlane` and `ClusterWorkflowPlane`

---

## Prerequisites

Before running the prompt, ensure the following are installed on your macOS machine:

| Tool | Install | Version used |
|------|---------|--------------|
| Colima | `brew install colima` | 0.8.x or later |
| kubectl | `brew install kubectl` | any recent |
| Helm | `brew install helm` | v3.x |
| Claude Code | `npm install -g @anthropic-ai/claude-code` | latest |

> **Resources required:** At least 7 CPU cores and 9 GB RAM available to the Colima VM. The install uses: `--cpu 7 --memory 9 --disk 100`.

---

## Step 1 — Add the openchoreo-install skill to Claude Code

Add just the `openchoreo-install` skill to Claude Code globally — you don't need the other skills in this repo for local installation:

```bash
claude skills add https://github.com/lakwarus/openchoreo-skills/tree/main/openchoreo-install -g
```

Verify it loaded:
```bash
claude skills list
# Should show: openchoreo-install
```

> The `-g` flag installs globally (available in all projects without any project-level config). Pointing at the skill subdirectory directly loads only that skill.

---

## Step 2 — Open Claude Code and run the prompt

Open Claude Code in any directory (no project context required for install):

```bash
claude
```

Then paste this prompt:

```
I want to try OpenChoreo on my local machine. I have Colima, kubectl, and Helm
installed. Please set up a fresh OpenChoreo environment on my local Colima
cluster using the openchoreo-install skill. Follow the local-colima.md guide
and install everything: control plane, data plane, and workflow plane.
```

That's it. Claude Code will execute the full installation autonomously.

---

## What Claude Code does

Claude Code reads `references/local-colima.md` from the `openchoreo-install` skill and executes each step:

### Step 1 — Start Colima
```bash
colima start \
  --vm-type=vz --vz-rosetta \
  --cpu 7 --memory 9 --disk 100 \
  --kubernetes --kubernetes-version v1.33.4+k3s1 \
  --network-address
```

### Step 2 — Install prerequisites
In sequence (each verified before the next):
1. Gateway API CRDs (experimental, v1.4.1)
2. cert-manager (v1.19.2)
3. External Secrets Operator (v1.3.2)
4. kgateway CRDs + controller (v2.2.1)
5. OpenBao (v0.25.6, using k3d dev-mode values)
6. Manually seeds all required secrets if the postStart hook didn't complete
7. Creates `ClusterSecretStore` with token auth

### Step 3 — Install control plane
1. Thunder identity provider (v0.26.0, using official k3d values — already set to `openchoreo.localhost`)
2. Backstage `ExternalSecret`
3. `openchoreo-control-plane` Helm chart (v1.0.0, k3d single-cluster values)
4. Patches `NODE_ENV=development` (chart default is `production`; auth config only has `development:` key)
5. Patches CoreDNS to resolve `openchoreo.localhost`, `api.openchoreo.localhost`, `thunder.openchoreo.localhost` → CP gateway ClusterIP

### Step 4 — Apply default resources
```bash
kubectl apply -f .../samples/getting-started/all.yaml
kubectl label namespace default openchoreo.dev/control-plane=true
```
Creates: default Project, DeploymentPipeline, Environments (dev/staging/prod), ComponentTypes (service, web-application, worker, scheduled-task), ClusterWorkflows, ClusterTraits.

### Step 5 — Install data plane
1. Copies `cluster-gateway-ca` cert to `openchoreo-data-plane` namespace
2. `openchoreo-data-plane` Helm chart (v1.0.0, k3d values — port 19080)
3. Registers `ClusterDataPlane` with `openchoreoapis.openchoreo.localhost` host
4. Updates CoreDNS to also resolve `openchoreoapis.openchoreo.localhost` → DP gateway ClusterIP

### Step 6 — Install workflow plane
1. Copies `cluster-gateway-ca` cert to `openchoreo-workflow-plane` namespace
2. `openchoreo-workflow-plane` Helm chart (v1.0.0, k3d values)
3. Applies Argo Workflow templates (checkout-source, buildpacks, dockerfile-builder, publish-image)
4. Registers `ClusterWorkflowPlane`

### Step 7 — Install observability plane
1. Creates namespace, copies CA, creates ExternalSecrets for OpenSearch credentials
2. `openchoreo-observability-plane` Helm chart (v1.0.0) on port 9080 (TLS disabled)
3. Installs modules in parallel: `observability-logs-opensearch`, `observability-metrics-prometheus`, `observability-traces-opensearch`
4. Reconfigures observer with `observer.openchoreo.localhost` hostname and internal Thunder URLs
5. Adds `observer.openchoreo.localhost` → obs gateway ClusterIP to CoreDNS
6. Registers `ClusterObservabilityPlane` with `observerURL: http://observer.openchoreo.localhost:9080`
7. Links data plane and workflow plane to the observability plane
8. Enables Fluent Bit log collection

---

## Results from the last run

**Date:** 2026-03-20
**OpenChoreo version:** v1.0.0
**Colima version:** 0.8.x
**k3s version:** v1.33.4+k3s1
**macOS:** Apple Silicon (M-series), macOS 25.3.0

### Timing

| Phase | Duration |
|-------|----------|
| Colima start | ~47 seconds |
| Prerequisites (cert-manager, ESO, kgateway, OpenBao) | ~2 minutes |
| Control plane (Thunder + Backstage + controller) | ~2 minutes |
| Data plane | ~1 minute |
| Workflow plane | ~30 seconds |
| Observability plane (core + 3 modules) | ~3 minutes |
| **Total** | **~9 minutes** |

### All planes healthy

```
=== Control Plane (openchoreo-control-plane) ===
backstage            1/1   Ready
cluster-gateway      1/1   Ready
controller-manager   1/1   Ready
gateway-default      1/1   Ready
kgateway             1/1   Ready
openchoreo-api       1/1   Ready

=== Data Plane (openchoreo-data-plane) ===
cluster-agent-dataplane   1/1   Ready
gateway-default           1/1   Ready

=== Workflow Plane (openchoreo-workflow-plane) ===
argo-server                   1/1   Ready
argo-workflow-controller      1/1   Ready
cluster-agent-workflowplane   1/1   Ready

=== Observability Plane (openchoreo-observability-plane) ===
cluster-agent-observabilityplane   1/1   Ready
controller-manager                 1/1   Ready
gateway-default                    1/1   Ready
kube-state-metrics                 1/1   Ready
metrics-adapter-prometheus         1/1   Ready
observer                           1/1   Ready
opentelemetry-collector            1/1   Ready
prometheus-operator                1/1   Ready
```

### Plane registrations

```
clusterdataplane.openchoreo.dev/default              Ready
clusterworkflowplane.openchoreo.dev/default          Ready
clusterobservabilityplane.openchoreo.dev/default     Ready
```

### CoreDNS configuration (final)

```
hosts {
  10.43.34.57   openchoreo.localhost
  10.43.34.57   api.openchoreo.localhost
  10.43.34.57   thunder.openchoreo.localhost
  10.43.154.89  openchoreoapis.openchoreo.localhost
  10.43.234.220 observer.openchoreo.localhost
  fallthrough
}
```
> ClusterIPs are assigned dynamically — yours will differ.

---

## Access URLs

| Service | URL |
|---------|-----|
| Console | `http://openchoreo.localhost:8080` |
| API | `http://api.openchoreo.localhost:8080` |
| Thunder (IdP admin) | `http://thunder.openchoreo.localhost:8080/develop` |
| Deployed apps | `http://<route>.openchoreoapis.openchoreo.localhost:19080` |
| Observer (observability) | `http://observer.openchoreo.localhost:9080` |

**Login:** `admin@openchoreo.dev` / `Admin@123`
**Thunder admin:** `admin` / `admin`

---

## Every session — start the port-forward

Chrome resolves `*.localhost` to `127.0.0.1` natively (no `/etc/hosts` needed). However, kubectl port-forwards are needed to route traffic from `localhost:8080` into the Colima VM. Run this in a dedicated terminal each time you restart Colima:

```bash
curl -fsSL https://raw.githubusercontent.com/lakwarus/openchoreo-skills/main/openchoreo-install/start-openchoreo-portforward.sh | bash
```

Or download once and run locally:
```bash
curl -fsSL https://raw.githubusercontent.com/lakwarus/openchoreo-skills/main/openchoreo-install/start-openchoreo-portforward.sh \
  -o start-openchoreo-portforward.sh
bash start-openchoreo-portforward.sh
```

The script auto-restarts all three port-forwards (`:8080`, `:19080`, `:9080`) if they die.

---

## Known issues and workarounds

| Issue | Root cause | Fix applied |
|-------|-----------|-------------|
| `NODE_ENV=production` breaks login | The Backstage Helm chart sets `NODE_ENV=production` but `app-config.yaml` only has an auth provider under the `development:` key — so auth start returns 404 | Patched with `kubectl patch --field-manager helm --type=json` after install. Re-apply after any `helm upgrade` of the control plane |
| In-cluster DNS fails for `*.openchoreo.localhost` | Colima's internal DNS (192.168.5.1) has DNS rebinding protection and doesn't know `*.openchoreo.localhost`. Without a CoreDNS override, pod-to-pod calls (Backstage → Thunder, API server → Thunder JWKS) fail | CoreDNS `hosts` block patched to map `*.openchoreo.localhost` → gateway ClusterIPs |
| OpenBao postStart hook may not complete | The `values-openbao.yaml` `postStart` lifecycle hook runs asynchronously. On a slow VM or cold start it may not finish before the pod is `Ready` | Claude Code checks and runs the seeding script manually if secrets are missing |
| `window.crypto.randomUUID` not available | OAuth PKCE flow uses `window.crypto.randomUUID` which requires a secure context. nip.io domains over HTTP are not secure contexts in Chrome | Solved by using `openchoreo.localhost` domains — Chrome treats `*.localhost` as secure contexts natively |

---

## Why `openchoreo.localhost` instead of nip.io

The official OpenChoreo k3d install uses `openchoreo.localhost` as the domain. This works out of the box because:

1. **Chrome resolves `*.localhost` → `127.0.0.1` natively** — no `/etc/hosts` entries needed on macOS or any OS with a modern browser
2. **Chrome treats `*.localhost` as secure contexts** — `window.crypto.randomUUID`, Web Crypto API, and other HTTPS-only browser APIs work over plain HTTP
3. **No DNS rebinding issues** — `*.localhost` never hits an external DNS server, so Colima's internal DNS rebinding protection is irrelevant

The Colima-native install now uses the k3d values files directly without any `sed` domain substitution, keeping it in sync with the official k3d path.
