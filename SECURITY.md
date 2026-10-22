# Security policy

This hobby project exposes an authenticated web terminal inside disposable sandboxes.
Run it only on loopback or a trusted network behind TLS and authentication. The trusted
backend controls the Docker daemon; Docker group/socket access is equivalent to host administration.
Do not expose the service directly to the public Internet or run untrusted tenant code on a shared production host.

Report vulnerabilities privately using [GitHub Security Advisories](https://github.com/abevz/devops-quests/security/advisories/new).
If private reporting is unavailable, ask maintainers to enable it without disclosing exploit details in an issue.
Only the latest tagged release is supported. No security response SLA is promised.
