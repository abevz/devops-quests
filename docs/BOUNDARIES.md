# Execution boundary

The baseline task is the owner's local prompt
`/home/demo/Projects/codex-prompts/2026-10-20-devops-quests.md`.
The current curriculum expansion follows
`/home/demo/Projects/codex-prompts/2026-10-21-devops-quests-book-levels.md`.

- Local repository and local commits only. No remote is configured.
- Docker endpoint is an explicit local Unix socket, never the current CLI context.
- Every top-level resource has the `devops-quests` label and installation ID.
  kind's immutable container label is `io.x-k8s.kind.cluster=<recorded cluster name>`:
  `devops-quests-<installation ID>` for new states, `devops-quests` for legacy states.
- Kubernetes commands always use the game's explicit kubeconfig and context.
  The player's credentials are namespace-scoped, not the setup administrator.
- No host Docker socket, home directory or ambient kubeconfig is mounted in a
  workstation. Only the game's generated client credentials are mounted read-only.
- An internal bridge and narrowly scoped host INPUT/FORWARD guards deny access
  outside the game, including the bridge gateway. Reset removes only those guards.
- A game namespace enforces restricted Pod Security; players cannot change its
  labels, create cluster roles or mount a node's filesystem.
- Explicit advanced grants are limited to one named synthetic PV/StorageClass
  or read-only admission/ApplicationSet objects. Static-Pod and controller
  repairs use finite backend adapters, never a host socket or admin kubeconfig.
- Nested Docker is private to a player and uses mutual TLS. It has no parent
  Docker socket. The daemon uses RootlessKit, with inner root mapped to outer
  UID 1000. Its outer container needs privileged startup; device visibility
  does not grant the inner daemon permission to open host block devices.
  Container isolation shares the kernel: this is trusted LAN
  training, not a service for hostile public tenants or a kernel-escape boundary.
- Network and filesystem isolation must pass actual probes before a bay is usable.
- deployment host changes have a separate capacity, backup, maintenance and firewall gate.
  No other guest, host network, ARC setting or Proxmox backup job is changed.
