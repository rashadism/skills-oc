---
name: openchoreo-install
description: |
  Use this for the **initial install** of OpenChoreo on a Kubernetes cluster: installing prerequisites, registering planes (control, data, workflow, observability) for the first time, troubleshooting installation failures, or tearing down an installation. Do NOT use for post-install operations (Helm upgrades, day-2 plane changes, registering additional planes) — those belong to `openchoreo-platform-engineer` or the official PE guide.
metadata:
  version: "1.0.0"
---

# OpenChoreo Install Guide

Help with installing OpenChoreo on a Kubernetes cluster. This skill covers the full single-cluster installation path: prerequisites, control plane, data plane, workflow plane, and observability plane.

> **PREREQUISITE**: Read `openchoreo-core/SKILL.md` and the relevant references under `openchoreo-core/references/` before reaching for skill-specific deep-dives. Core covers the resource model, `occ` install/login, the MCP tool catalog, and universal YAML schemas — none of which are repeated here.

## Scope

Use this skill for:

- Installing OpenChoreo from scratch on any Kubernetes cluster (EKS, GKE, AKS, DOKS, k3s, or self-managed)
- Installing and configuring prerequisites (cert-manager, external-secrets, kgateway, OpenBao)
- Registering planes (DataPlane, WorkflowPlane, ObservabilityPlane)
- Diagnosing installation failures (CRDs, TLS, LoadBalancer, identity)
- Uninstalling / cleaning up an installation

Pair with `openchoreo-platform-engineer` for post-install work: creating environments, pipelines, ComponentTypes, Traits, and Workflows.

## Reference routing

Read only what the task needs:

- `references/local-colima.md` — **start here for Colima users**; uses Colima's native k3s, no extra tools required — just `colima start` commands the user already knows
- `references/local-k3d.md` — **alternative local path** (any Docker environment); uses k3d with fixed localhost ports and plain HTTP — better for guaranteed Chrome browser access
- `references/prerequisites.md` — tool versions, cluster requirements, Gateway API CRDs, cert-manager, external-secrets, kgateway, OpenBao, ClusterSecretStore
- `references/control-plane.md` — TLS setup, Helm install, Thunder (identity provider), domain configuration, default resources
- `references/data-plane.md` — data plane Helm install, LoadBalancer resolution, TLS certificate, ClusterDataPlane registration
- `references/workflow-plane.md` — workflow plane Helm install, workflow templates, ClusterWorkflowPlane registration
- `references/observability-plane.md` — observability plane Helm install, OpenSearch/Prometheus/traces modules, ClusterObservabilityPlane registration, linking planes
- `references/cleanup.md` — full uninstall sequence

## Working style

1. **Ask for cluster type early** — Colima, Docker Desktop, EKS, GKE, AKS, k3s, or other. For Colima users, always use `references/local-colima.md` first — the only prerequisite is `colima start`. For Docker Desktop or other Docker environments, use `references/local-k3d.md`. For cloud clusters, use the standard path.
2. **Work step by step** — each plane depends on the previous one. Do not skip ahead.
3. **Verify before proceeding** — after each major step, run the health/readiness check before moving to the next plane.
4. **Use nip.io for domains** — the install uses `<ip>.nip.io` wildcard DNS; no external DNS configuration is needed.
5. **All TLS is self-signed by default** — the `openchoreo-ca` ClusterIssuer signs all certificates. For production, swap it for Let's Encrypt or a real CA.

## Installation order

```
1. Prerequisites (cert-manager, external-secrets, kgateway, OpenBao, ClusterSecretStore)
2. TLS (openchoreo-ca ClusterIssuer)
3. Control Plane — initial install → get LB IP → configure domain → Thunder → reconfigure with real hostnames
4. Default resources (kubectl apply all.yaml + label default namespace)
5. Data Plane — install → get LB IP → TLS cert → register ClusterDataPlane
6. Workflow Plane (optional) — install → workflow templates → register ClusterWorkflowPlane
7. Observability Plane (optional) — install → modules → TLS → configure → register → link planes
```

## Stable guardrails

- **Always resolve the LoadBalancer IP before setting the domain** — use `dig +short` on the hostname if `.ip` is empty (common on EKS and GKE)
- **EKS only:** patch both `gateway-default` services with `aws-load-balancer-scheme: internet-facing` — one in `openchoreo-control-plane`, one in `openchoreo-data-plane`
- **Single-node clusters:** use `--set gateway.httpPort=8080 --set gateway.httpsPort=8443` for data plane and `--set gateway.httpPort=9080 --set gateway.httpsPort=9443` for observability plane to avoid port conflicts
- **`-k` on all curl health checks** — TLS is self-signed; curl will fail without it
- **Workflow images use ttl.sh** — images expire after 24 hours; point to a real registry for production
- **Thunder changes need PVC deletion + reinstall** — don't patch Thunder in place if OIDC config is wrong; delete the PVC and reinstall

## Anti-patterns

- Skipping the `kubectl wait` steps — many later commands depend on resources being fully Ready
- Running `helm upgrade --reuse-values` before the initial install has completed
- Setting domains before the LoadBalancer IP is stable
- Proceeding to data plane registration before `cluster-gateway-ca` certificate is Ready in `openchoreo-control-plane`
- Using `occ login --client-credentials` with `service_mcp_client` — fails with `unauthorized_client`. Use browser-based `occ login` instead.
