# Saved learning Labs

The five Lab profiles cover the published Guides: Kubernetes, Ansible, OpenTofu,
Helm and GitOps. They are separate from scored attempts and do not change quest
progress. This is a private, trusted learning environment with a shared host
kernel. Kubernetes administration is confined to a separately owned kind
cluster, not a VM or a proven boundary against hostile kernel exploits.

## From a Guide to an observation

Open a Guide, predict the result, then open its matching Lab. Create the profile
once; subsequent visits open its saved workspace. Files are in `~/lab/examples`.
Each short and full experiment has `run.sh`, `check.sh`, and `cleanup.sh`. Read
the scripts before executing them: `check.sh` may deliberately change state,
produce an expected failure, or exercise a rollback. Run cleanup before repeating
an experiment. The full reference retains explanatory source snapshots; use the
adapted files for this Lab's paths, nodes, images and credentials.

Only one workspace can run across all accounts, including Training Bay. A busy
slot never stops another person's work. Stopped Labs retain storage and consume
no running slot. There is no automatic eviction of saved data and no promise of
unlimited disk space. The administrator must monitor Docker storage.

## Data contract

| Action | Saved files and resources | Processes and terminals |
|---|---|---|
| Navigate within the app | Preserved | Connected shell preserved |
| Reload page / login again | Preserved | New shell |
| Stop / backend restart | Container layers, named/anonymous volumes and metadata retained | Stopped |
| Resume | Same verified container IDs; no recopy of examples | Restarted |
| Reset | This Lab's files, cluster and volumes are deleted and recreated | Recreated |
| Delete | This Lab's resources are removed | Ended |

No new resources are silently substituted when a saved container is missing.
Reset is explicit. Replaced resources with unverified identities are refused,
including same-name objects. A failed stop keeps the global slot occupied until
ownership and shutdown can be confirmed. Partial preparation is retained for
inspection; reset is required before trying a fresh preparation.

The profile version covers its specification, examples, asset identities and
runtime implementation. Changed versions cannot overwrite a saved workspace.
Export its work first, then explicitly delete/recreate it. Stopping/deleting an
old version uses its recorded runtime configuration.

## Build assets and operate

Run `make bootstrap`, then `make lab-assets` on the Linux amd64 build machine.
The latter requires Go and the local Docker daemon. Images are pinned in
`labs/images.lock.json`; the collection archive and checksum are in
`labs/collections.lock.json`. Downloads and compilation happen before entering
the Lab. The browser workstation has no host Docker socket, host filesystem,
ambient kubeconfig, personal SSH key or Internet access.

Kubernetes includes two workers for real placement and drain experiments. Helm
and GitOps use a single private node. GitOps uses private Gitea and Argo CD;
Ansible has three SSH targets; OpenTofu has a separate TLS Docker daemon and
cached providers. S3/AWS and kernel/reboot exercises remain additional
practicums requiring a separately approved environment. They are labelled in
the coverage map, not reported as executed in these profiles.

| Profile | Configured container memory ceilings | Configured CPU ceilings |
|---|---|---|
| Kubernetes | 2 GiB control plane + 2 × 1 GiB workers + 512 MiB workstation | 1.5 + 2 × 0.5 + 0.5 |
| Ansible | 3 × 96 MiB targets + 512 MiB workstation | 3 × 0.25 + 0.5 |
| OpenTofu | 1 GiB daemon + 512 MiB workstation | 0.75 + 0.5 |
| Helm | 3 GiB node + 512 MiB workstation | 1.5 + 0.5 |
| GitOps | 3 GiB node + 256 MiB Gitea + 512 MiB workstation | 1.5 + 0.5 + 0.5 |

These are container ceilings, not a VM sizing benchmark. The backend, Docker,
image caches and saved volumes also need capacity. Local smoke logs record
actual observations. Before deployment, measure deployment host's free disk and peak
pressure under its real shared cgroup limit, record the evidence in the release
report, and verify syntax Quest remains available. Local measurements alone do
not establish VM capacity or authorize increasing its allocation.

## Recovery and release boundary

Cluster creation has a private, recorded worker and lock. If the backend exits
mid-creation, recovery waits for that bounded kind invocation before stopping
its nodes and freeing the shared slot. A worker that has not started is cancelled.
Recovery verifies the recorded Docker network ID, node image, cluster label and
creation time, then saves exact container IDs; later replacement containers are
never adopted. An unfinished Lab is retained for an explicit reset.

`devops-quests backup` backs up SQLite identities, progress and Lab records.
It does **not** back up Lab files, Docker volumes or container writable layers.
`devops-quests reset` resets Training Bay resources and retains saved Labs.

For a release, stop all workspaces and the application, take the SQLite backup,
and take a consistent host/VM storage snapshot covering the state directory and
Docker data. Verify that backup before any migration. A code-only rollback is
insufficient for changed Lab assets and does not restore deleted user data.
Do not run an old backend alongside this one: the old code does not enforce the
shared Lab slot. Keep the previous checkout, asset metadata and matching backup
for rollback. Test restoration on a disposable copy before deployment.

Training Bay teardown stops a shared kind node only when its exact ID was
recorded at creation. An older installation with only `kind-owner` metadata
does not provide that proof, so the new teardown leaves its node alone. Before
an upgrade, stop the old application and use its existing, reviewed reset
procedure to remove its disposable game cluster after taking the backup. The
new backend will create and record its own replacement when needed. This release
does not change the legacy reset command's ownership contract.
An interrupted first game-cluster creation that has not recorded its exact ID
has the same explicit-reset requirement; teardown never guesses that identity
from a name, image or network. This is separate from the Lab creation recovery
described above.

New Training Bay installations use a kind cluster name scoped to their
installation identity, so a local preview can coexist with the main checkout.
The name is persisted in `kind-cluster-name`. Existing states with kind metadata
retain the legacy `devops-quests` name; startup does not rename, adopt or delete
their cluster. Back up this metadata together with the installation state.

Local implementation and checks do not authorize deployment, service restarts,
resource increases or deletion of existing users' work. The release package must
include `labs/`, the editorial YAML files, new backend modules, built browser
assets, OCI archives, the collection archive and the diagnostic image with its
recorded identity. Re-run the verification suite and independent review for the
final revision before publication.
