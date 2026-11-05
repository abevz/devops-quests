# Development and delivery

For every quest-editing task, follow [docs/quest-authoring.md](docs/quest-authoring.md)
and cite the relevant principle numbers in the PR.

Work only in the authorized scope. Preserve accounts, progress, pending briefing hints,
Lab files and unrelated Docker resources. Never add AI attribution or contributor trailers.
No default credentials, personal infrastructure, user databases, logs or private keys belong here.

In the maintainer layout (a bare clone with worktrees) treat the `main` worktree as read-only
(update and status only): create a sibling worktree on a new branch from `origin/main` for
every task (`git -C main worktree add ../<task> -b <branch> origin/main`), push that branch
and open a PR. Never commit or push to `main` directly; remove finished worktrees with
`git worktree remove`.

Use one writer per worktree. Independent read-only review must cover the final changed
content before commit/publication; later source edits need renewed review. Keep evidence
outside Git. Verify actual entrypoints and fixture layouts before changing production behavior.

## Delivery rules

- A normal task ends when its reviewed PR is merged to main after green CI; do not tag,
  release or deploy as part of that task. The owner previews merged main locally using
  the persistent preview worktree described in CONTRIBUTING.md.
- A release is a separate task created and authorized by the owner. Its scope includes
  tagging, artifacts and deployment. Always require green CI and smoke after deployment;
  CI never starts sandboxes by default.
- Database schema changes: rehearse rollback and compare progress hashes.
- Interface changes: headed screenshots of the affected screens, using synthetic users.
- Level changes: run the matrix only for affected levels; solutions are included for this proof.
- Keep release artifacts/checksums/image digests bound to the source commit. Do not move tags.
- Deploy by immutable version/digest; block active attempts/Labs and pending briefing hints.
- Do not publish, merge or deploy without the owner's authorization.

Validate with `.venv/bin/python -m pytest -q`, `npm test`, `ruff check .` and
`python scripts/validate_i18n.py`. Excerpt provenance, code-block parity and diagram tests
are required. Native Linux amd64 is the qualified target; do not invent portability claims.

<!-- BEGIN DIBS INTEGRATION v:2 -->
This repo is coordinated by [dibs](https://github.com/abevz/dibs).

- **Canonical protocol**: run `dibs protocol`; source: `https://github.com/abevz/dibs/blob/main/docs/agent-protocol-v1.md`
- **GitHub issues**: follow the protocol section "Working from GitHub issues" for import, public result publication, and untrusted source text.
- **Identity**: `dibs` automatically infers your agent name and process PID from the process tree. You may optionally override this by exporting `DIBS_ACTOR=<agent-name>`.
- **Session cycle**: `ready → claim → heartbeat → handoff/close`
- **Lease tokens**: Agents never pass `--lease-token` on an executed command line, including shell expansion. Use `dibs issue run` for the lifecycle. For unavoidable manual steps, supply `DIBS_LEASE_TOKEN` in the environment or `DIBS_LEASE_TOKEN_FILE` pointing to a private mode-0600 file, and omit the flag.
- **Worktree hygiene**: implement in a sibling worktree when the coordinated checkout is a read/merge anchor; after removing a merged task worktree, use `dibs worktree prune --repo <repo-id>` (or `dibs worktree unregister --worktree <id>` for one known safe record).
- **Never** edit files without an active claim.
- **Never** touch the coordinator database.
- **Never** restate specs in issue descriptions — link them.
- **Never** close an issue without a note (`--note`) — the audit trail is for whoever comes after you.
<!-- END DIBS INTEGRATION -->
