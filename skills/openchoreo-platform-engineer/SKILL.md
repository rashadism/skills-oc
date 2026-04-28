---
name: openchoreo-platform-engineer
description: |
  Use this whenever an OpenChoreo task needs a platform-level change or investigation: cluster setup, Helm upgrades, plane connectivity, platform resources, ComponentTypes, Traits, Workflows, gateways, secret stores, identity, GitOps, observability, or cluster-side debugging. Prefer MCP tools, then occ, over kubectl. If the same task also involves deploying or debugging an application through `occ`, activate `openchoreo-developer` too instead of waiting to escalate later.
metadata:
  version: 1.0.0
---

# OpenChoreo Platform Engineer Guide

Help with OpenChoreo platform-level work. Keep this file generic and pull specifics from the reference docs or the live cluster only when needed.

> **PREREQUISITE**: Read `openchoreo-core/SKILL.md` and the relevant references under `openchoreo-core/references/` before reaching for skill-specific deep-dives. Core covers the resource model, `occ` install/login, the MCP tool catalog, and universal YAML schemas — none of which are repeated here.

## Scope and pairing

Use this skill for PE-owned work:

- Cluster-side setup, upgrades, and troubleshooting
- Helm, CRD, controller, or agent investigation
- Platform resources such as DataPlane, WorkflowPlane, ObservabilityPlane, Environment, DeploymentPipeline, Project, ComponentType, Trait, Workflow, and ClusterWorkflow
- Shared platform capabilities such as gateways, secret stores, registries, identity, RBAC, and observability

Activate `openchoreo-developer` at the same time when the task also includes any of these:

- Deploying or debugging an application
- Editing app-facing Component, Workload, ReleaseBinding, or `workload.yaml`
- Using `occ` to inspect or operate a developer workload

If both skills are available and the task touches both app behavior and platform behavior, use both immediately. Do not wait to fail on one side before loading the other.

## Working style

Prefer progressive discovery over memorized specifics:

1. Identify the exact plane, namespace, resource, or failure domain.
2. Inspect live state first using MCP tools, then `occ`, then the REST API. Use `kubectl` only when MCP and occ cannot reach the resource (e.g. plane-level CRDs, controller logs).
3. Read only the reference file that matches the task.
4. Make the smallest change that can prove or fix the issue.
5. Verify the result from the live cluster before moving on.

**Tool preference order: MCP tools → occ / REST API → kubectl (last resort)**

Treat the live cluster and current repo as the source of truth. If a remembered field name, example, or behavior conflicts with current output, trust the current output and then confirm in the relevant reference file or repository source.

Avoid loading all references up front. Pull them in only when the task requires that area.

## Reference routing

Foundational material lives in `openchoreo-core/references/` (concepts, CLI install/login, MCP tool catalog, universal YAML schemas). Read those first when the gap is foundational.

PE-specific material:

- `references/operations.md` for namespace provisioning, topology, multi-cluster connectivity, and upgrades
- `references/templates-and-workflows.md` for ComponentTypes, Traits, Workflows, CEL, and template rules
- `references/integrations.md` for secret stores, registries, identity, RBAC, webhooks, and API management
- `references/observability.md` for logs, metrics, traces, alerts, and notification channels
- `references/troubleshooting.md` for failure isolation, health checks, log locations, and common failure patterns
- `references/cli-platform.md` for PE-specific `occ` commands, platform resource creation patterns (Environment, DeploymentPipeline, Project), and plane YAML schemas (DataPlane, WorkflowPlane, ObservabilityPlane, NotificationChannel)
- `references/mcp-platform.md` for PE-specific MCP workflows (initial setup, register types/traits/workflows, validate observability) and PE-specific gotchas
- `references/gitops.md` for GitOps repository layout and release flow
- `references/community-modules.md` for pluggable gateways and observability backends
- `references/advanced-setup.md` for certificates, private Git, custom build flows, and identity-provider swaps
- `references/repo-and-context7.md` when the docs are not enough and you need controller logic, CRD definitions, or Helm chart details

## Discovery-first workflow

### 1. Classify the task

Decide whether the work is:

- Pure platform work
- App work that needs PE help
- A mixed task that needs both OpenChoreo skills

For mixed tasks, keep the app-facing thread and the platform-facing thread connected. Many deployment failures are caused by an interaction between Component config and platform config.

### 2. Inspect the current state before planning

Start with the smallest useful inspection:

- Resource YAML for the object already involved
- `status.conditions`
- Relevant controller, gateway, or agent logs
- Current Helm release values when the issue might be installation- or upgrade-related

Do not assume a field exists because it appeared in an older example. Inspect the current CR, schema, or docs before patching. This matters especially for overrides, plane registration, workflow configuration, and trait parameters.

### 3. Route to the right source of detail

After the first inspection, load the matching reference file. If the reference still leaves ambiguity:

- Inspect the repository or generated CRDs
- Use Context7 for current OpenChoreo docs
- Check the live object shape on the cluster

Keep the investigation targeted. Avoid a full-cluster inventory unless the failure is clearly systemic or the affected resource is still unknown.

### 4. Change one layer at a time

Platform tasks often span multiple layers:

- Helm install values
- control plane namespace resources
- remote plane resources
- gateway or secret backend configuration
- app-visible outcomes such as available types, workflows, or routes

Change the layer that is actually responsible, then re-check the dependent layers. Do not "fix" an application symptom by guessing at platform internals.

### 5. Verify with live evidence

Verification should come from the platform, not assumption:

- Resource conditions changed as expected
- Controller or agent logs show the new state
- Helm release and pod rollout are healthy
- The downstream app-facing symptom is gone

If the platform change succeeded but the app still fails, hand off to or continue with `openchoreo-developer`.

## Stable guardrails

- **Default to the `default` namespace.** Unless the user explicitly asks to create a new namespace, provision all environments, pipelines, and projects inside the existing `default` namespace. Always ask the user before creating a new namespace — new namespaces represent a significant organisational boundary and should be a conscious decision.
- **Prefer MCP tools → occ / REST API → kubectl (last resort).** Most platform resource management works without kubectl.
- `create_environment` and `create_deployment_pipeline` are not MCP tools. Environments use `occ apply -f`. Pipelines require `kubectl apply -f` due to an occ schema bug — see `references/cli-platform.md` → "Create a DeploymentPipeline".
- `create_project` via MCP supports a `deployment_pipeline` parameter — pass it explicitly to avoid defaulting to the `default` pipeline.
- `occ login --client-credentials` does not work with `service_mcp_client` (`unauthorized_client`). Use browser-based `occ login`.
- Upgrade order matters; do not move a remote plane ahead of the control plane.
- Scope matters; cluster-scoped and namespace-scoped resources are not interchangeable.
- `status.conditions`, live resource YAML, and current controller logs are better truth sources than memory.
- When a task needs exact controller behavior or CRD fields, inspect the repo or Context7 instead of guessing.
- Prefer reversible, inspectable changes over broad edits across many planes or namespaces.

## Anti-patterns

- Loading every reference file before identifying the actual problem
- Repeating stale examples without checking the current cluster or resource schema
- Performing wide cluster sweeps before checking the affected object and logs
- Treating app-level deployment symptoms as purely platform issues without checking the app resource chain
- Making several platform changes at once and losing the causal signal
- Creating a new namespace without asking the user — default to `default` unless explicitly told otherwise
- Attempting `occ login --client-credentials` with `service_mcp_client` — silent-ish failure (`unauthorized_client`) that wastes time
