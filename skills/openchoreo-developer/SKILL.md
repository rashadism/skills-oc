---
name: openchoreo-developer
description: |
  Use this whenever the task is about working with an application on OpenChoreo: deploying, updating, debugging, explaining resources, writing app-facing YAML, or using `occ`. If the task also needs kubectl access, platform resources, cluster-side debugging, or platform configuration changes, activate `openchoreo-platform-engineer` too instead of treating it as a later escalation.
metadata:
  version: "1.0.0"
---

# OpenChoreo Developer Guide

Help with application-level work on OpenChoreo. Keep this file lean, discover the current platform shape from `occ`, and read detailed references only when the task actually needs them.

> **PREREQUISITE**: Read `openchoreo-core/SKILL.md` and the relevant references under `openchoreo-core/references/` before reaching for skill-specific deep-dives. Core covers the resource model, `occ` install/login, the MCP tool catalog, and universal YAML schemas — none of which are repeated here.

## Scope and pairing

Use this skill for developer-owned work:

- Deploying a new app or service to OpenChoreo
- Debugging an existing Component, Workload, ReleaseBinding, or WorkflowRun
- Explaining OpenChoreo app concepts and resource relationships
- Writing or fixing app-facing YAML
- Adapting an application so it runs cleanly on OpenChoreo

Activate `openchoreo-platform-engineer` at the same time when the task also includes any of these:

- `kubectl` investigation
- platform resources such as DataPlane, WorkflowPlane, Environment, DeploymentPipeline, ComponentType, Trait, Workflow, or ClusterWorkflow authoring
- gateway, secret store, registry, identity, or other platform configuration
- a likely PE-side failure rather than an app-level configuration problem

If both skills are available and the task involves both deployment/debugging and platform behavior, use both immediately. Many OpenChoreo problems cross that boundary.

## Working style

Prefer progressive discovery:

1. Understand the application shape from the repo before editing YAML.
2. Check `occ` access, context, and the live resources already involved.
3. Discover only the cluster resources needed for this task.
4. Read the matching reference file only after you know which area is relevant.
5. Apply the smallest viable change and verify through live status and logs.

The current cluster output is more trustworthy than memory. Do not assume available ComponentTypes, Traits, Workflows, environments, or field names. Discover them from `occ` first.

Before inventing YAML, prefer live scaffolding and repository samples.

## Reference routing

Foundational material lives in `openchoreo-core/references/` (concepts, CLI install/login, MCP tool catalog, universal YAML schemas). Read those first when the gap is foundational.

Developer-specific material:

- `references/deployment-guide.md` for BYOI, source builds, `workload.yaml`, dependencies, overrides, deployment flow, and **deploying third-party/public apps with pre-built images**
- `references/cli-developer.md` for developer-specific `occ` commands (scaffold, deploy, logs, workflow run/logs, workload create, componentrelease/releasebinding generate) and gotchas
- `references/mcp-developer.md` for developer-specific MCP workflows (scaffold, build, deploy, inspect, multi-service third-party apps) and gotchas

When the task crosses into PE-managed capabilities, activate `openchoreo-platform-engineer`.

Before writing YAML from scratch, prefer `occ component scaffold` to generate a Component template from the live cluster.

## Discovery-first workflow

### 1. Inspect the repo and classify the app

Start by understanding what is being deployed:

- Services and runtimes
- Dockerfiles and build system
- ports, env vars, and inter-service dependencies
- whether the app fits a simple image-based path or a source-build path

Do not scaffold or patch resources until the application shape is clear.

### 2. Check `occ` access and current context

Confirm the basics early:

- `occ version`
- current control plane and login status
- namespace and project context

If connectivity or auth is missing, fix that before reasoning about app resources.

### 3. Discover only what this task needs

Use focused discovery instead of broad inventory:

- existing project, component, or release binding when names are known
- available ComponentTypes only if you need to scaffold or change the type
- available Workflows only if this is a source build
- environments and deployment pipelines only if deployment or promotion depends on them

If the component already exists, inspect it before scaffolding or rewriting it.

### 4. Prefer generated or observed shapes over guessed YAML

Use `occ component scaffold` for Components whenever possible. For existing resources, inspect the current YAML before editing.

If a field path matters, confirm it in the live resource, schema reference, or current docs before patching. This avoids stale assumptions around workflow config, overrides, and app-to-platform boundaries.

Use `occ component scaffold <name> --clustercomponenttype <workloadType/typeName>` (or `--componenttype` for namespace-scoped types) to generate a valid starting YAML. Pipe with `-o <file>` to save it.

### 5. Verify with live app evidence

Use OpenChoreo resources to verify:

- `occ component get`
- `occ releasebinding get`
- `occ component logs`
- `occ component workflow logs`

Trust deployed URLs and endpoint details from ReleaseBinding status instead of constructing them by hand.

## Stable guardrails

Keep these because they are durable and routinely useful:

- Default to MCP tools first, then `occ`; avoid `kubectl` — if the task genuinely needs it, that is a PE boundary or a mixed-skill task
- `occ <resource> get <name>` returns full YAML and is a primary debugging tool
- Prefer scaffolding and samples over hand-written first drafts
- Source-build Components use `spec.workflow`; `workload.yaml` belongs at the root of the selected `appPath`
- Use ReleaseBinding status for the actual deployed URLs
- When platform capabilities are missing or broken, escalate clearly or activate `openchoreo-platform-engineer`
- **For third-party/public apps: default to pre-built images (BYO), not source builds.** Source builds commonly fail because third-party Dockerfiles use multi-platform syntax (`ARG BUILDPLATFORM`) that OpenChoreo's buildah builder does not support. If a build exits 125 with a `BUILDPLATFORM` error, switch to BYO immediately
- **Before deploying any third-party app: fetch the official Kubernetes or Helm manifests** and extract every required env var per service — dependencies inject service addresses but do not provide `PORT`, feature flags, or vendor SDK disable flags
- **`create_component` without `workflow` for BYO image deployments** — adding a workflow to a BYO component causes unnecessary failed builds
- **`dependencies` in workload spec is an object containing an `endpoints` array** — `dependencies.endpoints[]`, not flat `dependencies[]`. Each entry uses `name` (the target endpoint name on the dependency component), not `endpoint`. Field renamed from `connections` in v1.0.0.
- **Cloud-native apps often bundle vendor SDKs** (profilers, tracers, exporters) that crash outside their target cloud. If a service crash-loops before logging "listening on port X", look for a native module load error and apply the relevant disable flag from the official manifests

## Escalation rule

When you hit a PE-owned issue, state it directly and make the ask concrete:

"To do X, we need Y configured on the platform side. Please ask the platform engineering team to Z."

Activate `openchoreo-platform-engineer` for the full PE escalation surface and resource taxonomy.

## Anti-patterns

- Running every discovery command before checking the resource already implicated
- Writing Components or overrides from memory when `occ` can scaffold or reveal the current shape
- Reusing old examples without checking the current workflow and schema model
- Guessing deployed URLs or route formats instead of reading ReleaseBinding status
- Treating a platform-side failure as an app-only problem after `occ` evidence points elsewhere
- Creating source-build components (with `workflow`) for third-party apps that have pre-built images — this produces failed builds and clutters the UI; always check for pre-built images first
- Omitting env vars from official manifests when deploying third-party apps — always fetch and apply the exact env vars the upstream manifests specify (`PORT`, feature flags, vendor SDK disable flags)
- Assuming a deployment is healthy because `status: Ready` without checking application logs — a crash-looping container can briefly appear Ready; always confirm with `query_component_logs`
- Putting connection entries directly under `dependencies:` as a flat list — the canonical shape is `dependencies.endpoints: [...]`, with `name` for the target endpoint (not `endpoint`)
- Assuming dependency-injected service addresses are the only env vars needed — many apps also require `PORT`, telemetry disable flags, and optional service placeholders to start cleanly
