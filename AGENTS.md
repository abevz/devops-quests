# Development and delivery

Work only in the authorized scope. Preserve accounts, progress, pending briefing hints,
Lab files and unrelated Docker resources. Never add AI attribution or contributor trailers.
No default credentials, personal infrastructure, user databases, logs or private keys belong here.

Use one writer per worktree. Independent read-only review must cover the final changed
content before commit/publication; later source edits need renewed review. Keep evidence
outside Git. Verify actual entrypoints and fixture layouts before changing production behavior.

## Delivery rules

- Always: green CI and smoke after deployment. CI never starts sandboxes by default.
- Database schema changes: rehearse rollback and compare progress hashes.
- Interface changes: headed screenshots of the affected screens, using synthetic users.
- Level changes: run the matrix only for affected levels; solutions are included for this proof.
- Keep release artifacts/checksums/image digests bound to the source commit. Do not move tags.
- Deploy by immutable version/digest; block active attempts/Labs and pending briefing hints.
- Do not publish, merge or deploy without the owner's authorization.

Validate with `.venv/bin/python -m pytest -q`, `npm test`, `ruff check .` and
`python scripts/validate_i18n.py`. Excerpt provenance, code-block parity and diagram tests
are required. Native Linux amd64 is the qualified target; do not invent portability claims.
