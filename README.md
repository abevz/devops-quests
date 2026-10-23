# DevOps Quests

[![CI](https://github.com/abevz/devops-quests/actions/workflows/ci.yml/badge.svg)](https://github.com/abevz/devops-quests/actions/workflows/ci.yml)

A self-hosted hobby project for practising DevOps incidents in real, isolated sandboxes, with 130 quests, bilingual Guides and persistent Labs. No cloud account is required.

Designed and operated by [Aleksey Bevz](https://www.linkedin.com/in/aleksey-bevz/). See [About and authorship](#about-and-authorship) for the development method.

**Security:** The web terminal is a remote shell inside sandboxes. Run locally or on a trusted network behind TLS and authentication. The backend controls Docker with host-administrator privileges; this is not a public multi-tenant service.

![Level map from a clean Linux installation with a synthetic demo account](docs/screenshots/level-map.png)

## What's inside

The [catalog](levels.yaml) contains **130 quests** across four difficulty bands:

| Track | Quests | Examples |
| --- | ---: | --- |
| Kubernetes | 47 | Workloads, networking, storage, Helm upgrades and release diagnosis |
| Ansible | 23 | Inventory, permissions, handlers and SSH targets |
| OpenTofu | 24 | Modules, state, dependencies and local providers |
| Platform | 23 | GitOps with Gitea/Argo CD, registries and Vault |
| Boss | 13 | Incidents that combine several tools and checks |

Helm topics are part of the Kubernetes track; GitOps topics are part of Platform.

- **29 English/Russian Guides** combine short runnable examples with complete references. [Guide example](docs/screenshots/guide.png).
- **Five persistent Lab profiles:** Kubernetes (three-node cluster), Ansible, OpenTofu, Helm and GitOps. Workspaces retain files across Stop/Continue.
- **Interview drill** offers questions and self-check points from completed quests, plus nine theory topics. It does not require a cloud account.
- **Reference solutions** are included in [`solutions/`](solutions/) and drive the opt-in real-sandbox test matrix.

## How it works

1. **Separate runtimes and ownership.** Attempts use scoped kind, nested Docker or SSH-target environments; cleanup checks installation ownership. [Runtime design](docs/ARCHITECTURE.md#runtime-and-ownership).
2. **Offline sandboxes.** Internal Docker networks and per-installation guards block Internet, host and other bridge access. Assets are prepared before a learner starts. [Network boundary](docs/ARCHITECTURE.md#network-boundary).
3. **Server-side goal checks.** Scoped checks inspect the resulting workloads and files; passing a level depends on its objectives, not command-history matching. [Goal checks](docs/ARCHITECTURE.md#goal-checks).
4. **Immutable release identity.** Tags produce checksummed artifacts and GHCR image references pinned by digest; the release manifest binds files to a source commit. [Release identity](docs/ARCHITECTURE.md#release-identity).
5. **Recoverable upgrades.** The deployment contract keeps data outside releases and closes writes for backup, migration and smoke checks. Host-specific deploy/rollback operators, maintained separately, use a durable recovery journal. [Upgrade boundary](docs/ARCHITECTURE.md#upgrades-and-recovery).
6. **Solutions as executable evidence.** Opt-in integration runs reference solutions against real goal checks. Default PR CI validates curriculum contracts, Python/JS code, bilingual content and packaging without starting sandboxes. [Verification](docs/ARCHITECTURE.md#verification).
7. **Clean-install qualification.** Native and Compose installations were exercised on fresh Ubuntu LTS VMs through level 1, with isolation probes and synthetic accounts. [Qualification scope](docs/ARCHITECTURE.md#qualification).

## Quick start

Use native **Linux x86_64 with Docker Engine/Compose v2**, at least **4 vCPU / 8 GB RAM / 40 GB free disk**. macOS/Windows Docker Desktop are not supported; use a Linux VM. See the [full requirements and Lab measurements](docs/INSTALL.md#requirements).

Download all five assets from [v1.0.0](https://github.com/abevz/devops-quests/releases/tag/v1.0.0) into an empty directory. These commands assume both `DQ_ADMIN_USER` and `DQ_ADMIN_PASSWORD` are unset; for [first-start credentials supplied through the environment](docs/INSTALL.md#quick-start), omit the last command. From that directory:

```sh
sha256sum --check SHA256SUMS
tar -xzf devops-quests-v1.0.0.tar.gz
docker compose up --build -d
docker compose exec app python -m devops_quests init-admin --username demo
```

Enter your own password at the hidden prompt. The first start prepares offline assets; sign in at <http://127.0.0.1:8766/> once the backend is ready. There are no default credentials.

[Installation and operations](docs/INSTALL.md) covers source builds, cloud-init, startup time, persistent data, backups, removal and upgrades.

## About and authorship

Designed, specified, reviewed and operated by [Aleksey Bevz](https://www.linkedin.com/in/aleksey-bevz/).
Most of the code was written by AI coding agents working to that design; the architecture, requirements,
curriculum, acceptance checks, infrastructure and operations are mine.

## Contributing and documentation

- [Architecture](docs/ARCHITECTURE.md), [contribution guide](CONTRIBUTING.md), [security reporting](SECURITY.md) and [release rules](docs/RELEASING.md).
- Interface and learning content are English/Russian. Other languages are outside this release.
- Screenshots use a synthetic `demo` account. No owner accounts, databases or personal infrastructure are shipped.

Licensed under Apache-2.0. Third-party notices and the companion examples' MIT notice are retained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No book prose, questions or illustrations are redistributed. There is no support or availability SLA.
