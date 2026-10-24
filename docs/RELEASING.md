# Releasing

The public repository is the sole code source. Deployment integrations belong outside
this repository. Do not move release tags or rebuild an already published version.

## Required delivery checks

Always: green CI and smoke after deploy. Schema changes require rollback rehearsal and
progress-hash comparison. UI changes require headed screenshots of affected screens with
synthetic users. Level changes require the affected level matrix, not every sandbox.
Default PR/push CI runs unit tests, Ruff, JS tests (including diagrams), localized excerpt
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

## Verify the running version

After signing in, read the version and short commit at the bottom of the menu or
in Profile / Settings. They come from the server's installed `RELEASE.json`, not
a client-side version constant. A source install shows its Python package version
and checkout commit, or `dev`. Anonymous requests do not receive build metadata.

## Enable release notices

The feature is off by default. Explicitly set `DQ_UPDATE_CHECK=1` to allow the
background GitHub Releases API check; configure `DQ_UPDATE_REPO` and choose
`DQ_UPDATE_HINT=deploy|compose|none` for the installation. See
[installation settings](INSTALL.md#optional-admin-release-notice).

An admin notice links to release notes and optionally supplies a copyable operator
command or Compose update instructions. Only a newer stable semantic version is
offered; drafts and pre-releases are ignored. Attempts are persisted and limited
to one per 24 hours for the configured repository. Network failures stay in logs
and never block the app. There is no root operation or self-upgrade endpoint in
the web process: release, deployment and rollback remain operator actions.

## Offline dependencies (Linux amd64 / CPython 3.13)

The tag workflow restores `ci-dependencies.lock.json` package caches from the
`deps-1` GitHub prerelease. Their SHA-256 values bind the Python wheels and npm
cache; npm additionally checks `package-lock.json` integrity. CI uses pip
`--no-index`, npm `--offline`, and builds Python packages without build isolation.
No sandbox is started in CI.

`build-images.lock.json` records the v1.1.0 GHCR image digests and hashes of image
build inputs. `prepare_assets.py --release-build` refuses changed inputs and
reuses these images instead of contacting upstream registries, apt or PyPI.
`publish_images.py` copies only the digest-verified project mirrors. Refresh the
snapshot through a reviewed dependency update when changing image inputs; the
explicit developer `--source` path still builds from upstream sources.

Collections and tool archives have ordered sources in their locks, with the
project's dependency Release first. A failed HTTP request or checksum proceeds
to the next source in the developer/source path. Release builds restrict this list
to project GitHub sources and fail closed; they never fall back to third-party
servers. Nothing accepts bytes with a different pinned checksum.
The dependency Release is a prerelease, never latest; do not replace its assets
or move its tag. Publish a new dependency Release and update locks instead.

Each application Release contains a separate original collection archive and
`devops-quests-dependencies-linux-amd64.tar.gz` (tools and wheels), listed in both
`RELEASE.json.dependencies` and `SHA256SUMS`. The VM operator downloads and checks
these assets before installing Python requirements with `--no-index` and
`--require-hashes`. `prepare_assets.py` verifies already staged tools/collections
and pulls only the project's immutable GHCR references. It refuses missing or
corrupt dependency files instead of using a network fallback during deployment.

Keep release notes in `docs/releases/<tag>.md` before pushing the immutable tag.
Older Releases without dependency metadata keep the operator's legacy install
path, including its upstream network requirements. Rollback to an already
prepared v1.1.0 installation reuses its retained venv and assets without installing
or downloading dependencies. Do not delete old releases to reclaim space during
a deployment.
