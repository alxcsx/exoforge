# ADR 001: Exoforge MVP Architecture Invariants

- **Status**: Accepted
- **Date**: 2026-11-06
- **Context**: Setting architectural boundaries for the Exoforge MVP release.

---

## 1. Context & Problem Statement

Exoforge previously evolved with dual terminology ("plugin" and "extension"), legacy fallback paths (`plugins_csharp`, `PLUGINS_PATH`), speculative multi-tenancy (`title_id` and `studio_id` carried across operational databases and routing), in-place binary deployments, and sprawling container configurations (including unused Kubernetes manifests).

To deliver a rock-solid, production-ready MVP for Unity developers, we establish permanent architectural invariants and eliminate dead weight.

---

## 2. Decision Outcomes

### Invariant 1: Terminology is Exclusively "Extension"
- The platform uses **extension** everywhere: modules, registries, supervisors, runners, directory trees, manifests, CLI commands, C# attributes, dashboard copy, and APIs.
- Legacy `plugin` aliases, fallback paths (`plugins_csharp`, `PLUGINS_PATH`), and compatibility shims are removed completely.

### Invariant 2: Single-Title Instance Tenancy
- One Exoforge instance hosts **one title** in one environment (`dev`, `staging`, `prod`).
- Multi-title and multi-tenant routing scaffolding is purged from operational schemas, ETS tables, and routing keys.
- Authorization scopes (`admin > staff > player > guest`) and project metadata operate within the scope of the instance.

### Invariant 3: Unity Workspace Layout & Compilation Invariants
- The developer workspace lives inside the Unity project repository, separated by compilation boundary:
  ```
  MyUnityGame/
  ├── Assets/
  │   └── Exoforge/
  │       ├── Generated/
  │       │   ├── ExoforgeServices.g.cs     # Generated client stubs (compiled by Unity)
  │       │   └── Exoforge.Generated.asmdef  # Isolated compilation graph
  │       └── Resources/
  │           └── exoforge.json             # Runtime endpoint connection config
  └── Exoforge/                             # Outside Assets/ (invisible to Unity AssetDatabase)
      ├── exoforge.json                     # Workspace config & environment definitions
      ├── extensions/                       # Editable C# extension sources (.NET 10)
      └── .exoforge/                        # Git-ignored local build & staging cache
  ```
- Extensions are editable C# source locally and compile against modern .NET without interfering with Unity's internal compiler.
- Generated client code **must** reside under `Assets/Exoforge/Generated/` so Unity compiles it into `Assembly-CSharp` via `Exoforge.Generated.asmdef`.

### Invariant 4: No Custom Package Manager for MVP
- Third-party extensions are distributed as source archives (.zip / .tar.gz) or Git repositories and extracted directly into `Exoforge/extensions/<id>/`.
- Custom package manager machinery (`exo extension add <url>`, lockfiles, remote resolvers) is omitted from MVP scope.

### Invariant 5: Manifest Standard is `manifest.json`
- Each extension declares its contracts, dependencies, and capabilities in `manifest.json`.
- The manifest schema is unified across native C# (generated via `Exoforge.Extension.Generator` / Roslyn) and standard Elixir extensions.

### Invariant 6: Atomic Extension Deployment & Rollback
- Pushing an extension to an instance follows a transactional lifecycle:
  `source → build → validate → stage → probe (hello handshake) → atomic activate → rollback retention`.
- Active extensions run from an isolated, immutable directory. Pushes never overwrite running binaries in-place.
- A failed handshake or crash on boot aborts the stage without affecting the active extension.

### Invariant 7: VPS Container Deployment
- Production deployments target Linux VPS containers via Docker Compose or Podman Compose with Caddy handling TLS reverse-proxying.
- Mutable Git checkout deployments on servers are replaced by immutable tagged Docker images (`ghcr.io/exoforge/server:<version>`).
- Kubernetes manifests are archived outside the MVP critical path.

### Invariant 8: Test Tiering (Fast PR vs. Gated Releases)
- Normal local runs and PR checks remain sub-second (unit tests, extension build tests, SDK tests).
- Heavy vertical slices (live E2E WebSocket loop, cluster benchmark, cold-boot container tests) are gated behind release tags and manual triggers.

---

## 3. Consequences

- **Positive**: Drastically simpler mental model, zero dead code or misleading aliases, robust deployment reliability, immediate developer feedback in Unity.
- **Negative**: Breaking changes for any existing third-party code relying on legacy `plugin` naming or paths. (Acceptable during pre-production MVP).
