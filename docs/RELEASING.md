# Releasing

The public repository is the sole code source. Deployment integrations belong outside
this repository. Do not move release tags or rebuild an already published version.

## Required delivery checks

Always: green CI and smoke after deploy. Schema changes require rollback rehearsal and
progress-hash comparison. UI changes require headed screenshots of affected screens with
synthetic users. Level changes require the affected level matrix, not every sandbox.
Default PR/push CI runs unit tests, Ruff, JS tests (including diagrams), bilingual excerpt
and operational-code validators, bundle checksum validation, packaging and public hygiene.
No sandbox is started and no user secret is required by that CI.

## Owner publication

After review and successful clean-install tests, the owner creates a version tag. The tag
workflow first runs the same CI, builds pinned offline assets, publishes all sandbox and
Lab images to GHCR, and records exact `image@sha256:...` references in the release-only
`release-images.lock.json`. The lock includes the source commit and linux/amd64 platform.
Source builds continue to use the upstream digest locks as an alternative.

First publication also requires the owner to check each newly created GHCR package's
visibility and set it to **Public**, then verify every locked digest can be pulled without
Docker credentials. GitHub defaults new personal-account container packages to private;
creating a public source repository does not prove anonymous image access. This one-time
owner step follows the first tag build and precedes announcing the release or qualifying
GHCR installation. See [GitHub's package visibility instructions](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).

The workflow builds local web bundles, Python wheel/sdist, a complete runtime/source
tarball and SHA256SUMS, then attaches them to GitHub Release. The tarball's RELEASE.json
records the commit and every contained file hash. Wheel resources are installed under
`share/devops-quests`. Generated bundles/images/state are not claimed to be Git source.

GHCR mirrors preserve the curriculum image manifests and offline aliases. Four outer
services with multi-platform upstream indexes use verified local image identities from
`.state/host-images.json`; those identities participate in the Lab version fingerprint.
Published images may retain upstream multi-platform metadata, but the application/tooling
is **amd64 only**. No arm64 support is claimed.

Only the workflow receives package/content write permissions, using GitHub's short-lived
GITHUB_TOKEN. Pin actions by commit. Configure protected tags/environments on the hosting
service; this repository does not claim those server settings are already enabled.
See [GitHub's official publishing guide](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images).

## Verify and install

Download SHA256SUMS and the versioned tarball/wheel/sdist/image lock from the same trusted
GitHub Release over HTTPS. Verify filenames and SHA256 before extraction; reject absolute
paths, traversal, special files and unexpected symlinks. Keep the artifact and source commit
receipts outside the runtime state. Do not execute an unverified installer downloaded from a mutable branch.

```sh
sha256sum --check SHA256SUMS
```

Run `python3 scripts/prepare_assets.py` from the extracted directory to fetch only digest-pinned
release images and checksum-verified tools/collections, or `--source` to build from the pinned
source inputs. Source builds need Go and can consume more temporary disk/time. Then follow
README's loopback start and explicit administrator initialization. No default credential exists.

## Upgrade and rollback contract

Refuse active quest attempts, pending briefing hints and active/transitional Labs. Stop the
backend, back up SQLite with its backup API and integrity/hash checks, and preserve Lab files,
containers, volumes and images separately. Prepare a new immutable release and isolated venv;
never overwrite the old release or destructively prune its assets.

Keep writes closed throughout migration and authenticated smoke. A deploy integration should
use an edge maintenance gate to allow only its loopback smoke token while rejecting other traffic. Compare
schema/progress before opening traffic. On failure before reopening writes, switch back and
restore the quiesced database only if the migration changed it. Once writes reopen, never
silently replace live data from the old backup: require compatibility on a fresh copy or an
explicit data migration. Pending briefing hints must survive; rollback to code without their
transfer contract is refused while those records exist.

Smoke must cover the frontend, login, protected APIs returning401 anonymously, and an actual
authenticated request. Before opening traffic, also run level 1 (Image identity) and Stop
through the application API as a synthetic `release-smoke` user, using the installed release's
GHCR assets. Verify a ready workstation and the pinned image in CRI, then verify the attempt
and its owned node have stopped. A successful login/state request alone cannot qualify a
release: it does not exercise OCI import. Use isolated synthetic state and installation-owned
resources so learner accounts, progress, hints and saved Labs remain unchanged. A failure must
keep traffic closed and enter the integration's recovery path. This sandbox check belongs to
deployment qualification; default PR/push CI must still never start sandboxes.
Deployment-specific HTTPS chooser/routing checks and the smoke implementation belong to the
private integration. Keep the prior symlink/version and a tested rollback command.

Saved Labs pin runtime assets and code fingerprints. Incompatible saved Labs must block an
upgrade rather than be reset or deleted. Their data must remain available to the old release;
this project does not promise transparent migration across incompatible runtime versions.

## Before public publication

Use locally built artifacts and the same digest identities in disposable Linux install tests;
never claim a GHCR pull or hosted workflow run before publication. Record exact local evidence.
For a test-only offline transfer, record the verified asset cache with `scripts.asset_cache`,
copy only its listed files and `.state/assets-ready.json` (never `.state/runtime`), and save/load
each of its seven Docker image IDs in a separate archive. Startup verifies all file hashes,
source inputs and loaded image IDs before reusing this cache. This is a local qualification
path; normal release installs fetch their pinned GHCR references automatically.
Creating the public repository, pushing, creating the first tag and merging deployment PRs are
owner actions. Do not perform them as part of local preparation.
