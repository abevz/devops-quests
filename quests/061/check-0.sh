set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
test "$(kubectl auth can-i patch secret/station-repository -n "$ARGO_NAMESPACE")" = yes
test "$(kubectl auth can-i list secrets -n "$ARGO_NAMESPACE")" = no
test "$(kubectl auth can-i patch secret/unrelated -n "$ARGO_NAMESPACE")" = no
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_result_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_ACCESS'
source platform.env
kubectl -n "$ARGO_NAMESPACE" get secret station-repository -o json | jq -e --arg password "$GIT_PASSWORD" '(.data.password|@base64d)==$password' >/dev/null
DQ_LEGACY_ACCESS
)
[ $? -eq 0 ] || dq_result_failed=1
(
set -euo pipefail
source platform.env
python3 -I - <<'DQ_GIT_ACCESS'
import base64
import hashlib
import json
import os
import stat
import subprocess
import time
from pathlib import Path
from urllib.parse import urlsplit

deadline = time.monotonic() + 12
failed = False


def reject(marker):
    global failed
    failed = True
    print('Git delivery access is incomplete: ✗ [DQ:' + marker + ']')


def execute(args):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(args[0], 0)
    return subprocess.check_output(args, stderr=subprocess.DEVNULL,
                                   timeout=min(3, remaining),
                                   env=dict(os.environ, GIT_TERMINAL_PROMPT='0'))


def authority(value):
    parsed = urlsplit(value)
    if parsed.query or parsed.fragment:
        raise ValueError('not a direct repository URI')
    return parsed.scheme, parsed.hostname, parsed.port, parsed.path.rstrip('/')


try:
    receipt = json.loads(Path('/run/dq/facts/0/delivery-access.json').read_text())
    secret = json.loads(execute(['kubectl', '--request-timeout=2s', '-n', receipt['credentialNamespace'],
                                 'get', 'secret', receipt['credentialName'], '-o', 'json']))
    if secret['metadata']['uid'] != receipt['credentialUID']:
        reject('credential_identity')
    data = {key: base64.b64decode(value, validate=True).decode()
            for key, value in secret.get('data', {}).items()}
    if (data.get('url') != receipt['repoURL'] or data.get('username') != receipt['username']
            or data.get('type') != 'git'
            or secret['metadata'].get('labels', {}).get('argocd.argoproj.io/secret-type') != 'repository'):
        reject('credential_binding')
    password = data.get('password', '')
    if hashlib.sha256(password.encode()).hexdigest() != receipt['passwordSha256']:
        reject('credential_value')
    application = json.loads(execute(['kubectl', '--request-timeout=2s', 'get', 'application',
                                      receipt['applicationName'], '-o', 'json']))
    if application['metadata']['uid'] != receipt['applicationUID']:
        reject('application_identity')
    basic = base64.b64encode((receipt['username'] + ':' + password).encode())
    for path in (Path.home() / '.gitconfig', Path('repository/.git/config')):
        if path.exists():
            contents = path.read_bytes()
            if (password.encode() in contents or basic in contents) and stat.S_IMODE(path.stat().st_mode) & 0o077:
                reject('git_storage')
                break
    try:
        resolved = execute(['git', '-C', 'repository', 'ls-remote', '--get-url', receipt['repoURL']]).decode().strip()
        if authority(resolved) != authority(receipt['repoURL']):
            reject('git_target')
        else:
            rows = execute(['git', '-C', 'repository', 'ls-remote', receipt['repoURL'], 'refs/heads/main']).decode().splitlines()
            if rows != [receipt['revision'] + '\trefs/heads/main']:
                reject('git_access')
    except subprocess.CalledProcessError:
        reject('git_access')
except subprocess.TimeoutExpired:
    reject('git_budget')
except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
    reject('git_observation')
raise SystemExit(failed)
DQ_GIT_ACCESS
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; .spec.source.repoURL==$url and (.spec.source.path | same_dir("manifests")) and .spec.source.targetRevision=="main"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-61
)
[ $? -eq 0 ] || failed=1
exit "$failed"
