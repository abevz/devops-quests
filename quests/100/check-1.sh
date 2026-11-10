set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
failed=0
if ! git -C repository fetch origin main >/dev/null 2>&1; then printf '%s\n' 'git fetch origin main: ✗ [DQ:fetch]'; failed=1; fi
rev=$(cat release-commit 2>/dev/null || true)
if ! test -n "$rev" || ! test "$(git -C repository rev-parse origin/main 2>/dev/null)" = "$rev"; then printf '%s\n' 'origin/main = release-commit: ✗ [DQ:origin]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
source platform.env
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

from dq_check import named as _dq_named

def named(items, name):
    return _dq_named(items, name, error="named identity")

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="named identity", ignore_non_mappings=True)

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    image=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image']
    import yaml
    subprocess.check_call(['git','-C','repository','fetch','origin','main'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=8)
    d=yaml.safe_load(subprocess.check_output(['git','-C','repository','show','origin/main:manifests/board.yaml'],stderr=subprocess.DEVNULL,timeout=4));require(d.get('kind')=='Deployment' and d.get('metadata',{}).get('name')=='board','git_image');w=worker(d)
    require(w.get('image')==image,'git_image')
    variable=named(w.get('env',[]),'ROUTE_SECRET');ref=variable.get('valueFrom',{}).get('secretKeyRef',{})
    require('value' not in variable and set(variable.get('valueFrom',{}))=={'secretKeyRef'} and ref.get('name')=='route-secret' and ref.get('key')=='value','git_env')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'git_image'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
failed=0
rev=$(cat release-commit 2>/dev/null || true)
app=$(kubectl get application board -o json 2>/dev/null || true)
check_app() { local label=$1 expression=$2; if ! jq -e --arg rev "$rev" --arg url "$GIT_URL" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check_app 'repoURL = GIT_URL [DQ:repo]' '.spec.source.repoURL==$url'
check_app 'path = manifests [DQ:path]' '(.spec.source.path | (startswith("/")|not) and ([splits("/") | select(.!="" and .!=".")]==["manifests"]))'
check_app 'targetRevision = main [DQ:target]' '.spec.source.targetRevision=="main"'
check_app 'selfHeal = true [DQ:selfheal]' '.spec.syncPolicy.automated.selfHeal==true'
check_app 'prune = true [DQ:prune]' '.spec.syncPolicy.automated.prune==true'
check_app 'sync status = Synced [DQ:synced]' '.status.sync.status=="Synced"'
check_app 'health status = Healthy [DQ:health]' '.status.health.status=="Healthy"'
check_app 'sync revision = release-commit [DQ:release_revision]' '.status.sync.revision==$rev'
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

from dq_check import named as _dq_named

def named(items, name):
    return _dq_named(items, name, error="named identity")

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="named identity", ignore_non_mappings=True)

def require(good, marker):
    if not good:raise AssertionError(marker)

from dq_check import current_pods

def pod_worker(pod):return named(pod.get('spec',{}).get('containers',[]),'worker')

from dq_check import pull_secret_names as pull_names

try:
    d=get('deployment','board');w=worker(d);active=current_pods(d,get('replicasets'),get('pods'))
    image=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image']
    require(w.get('image')==image and all(pod_worker(p).get('image')==image for p in active),'board_image')
    require(w.get('imagePullPolicy')=='Always' and bool(active) and all(pod_worker(p).get('imagePullPolicy')=='Always' for p in active),'board_policy')
    require(all(pull_names(p)=={'registry-pull'} for p in active),'board_secret')
    variable=named(w.get('env',[]),'ROUTE_SECRET')
    reference=variable.get('valueFrom',{}).get('secretKeyRef',{})
    require('value' not in variable and set(variable.get('valueFrom',{}))=={'secretKeyRef'} and reference.get('name')=='route-secret' and reference.get('key')=='value','board_env')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'board_image'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_3]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
failed=0
if ! test "$(kubectl get secret route-secret -o json 2>/dev/null | jq -er .data.value 2>/dev/null | base64 -d 2>/dev/null)" = north-secret; then printf '%s\n' 'secret/route-secret value = north-secret: ✗ [DQ:secret]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
failed=0
umask 077
header=$(mktemp)
trap 'rm -f "$header"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$header"
if ! curl -fsS --max-time 3 -H @"$header" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -e '.data.data.value=="north-secret"' >/dev/null 2>&1; then printf '%s\n' 'Vault reader dispatch value = north-secret: ✗ [DQ:reader]'; failed=1; fi
if ! test "$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' -H @"$header" "$VAULT_ADDR/v1/secret/data/other" 2>/dev/null)" = 403; then printf '%s\n' 'Vault reader other path HTTP 403: ✗ [DQ:denied]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
kubectl rollout status deployment/board --timeout=3s
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

from dq_check import named as _dq_named

def named(items, name):
    return _dq_named(items, name, error="named identity")

from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="named identity", ignore_non_mappings=True)

def require(good, marker):
    if not good:raise AssertionError(marker)

from dq_check import current_pods

def pod_worker(pod):return named(pod.get('spec',{}).get('containers',[]),'worker')



from dq_check import ready_image

try:
    d=get('deployment','board');w=worker(d);active=current_pods(d,get('replicasets'),get('pods'))
    image=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image']
    require(w.get('image')==image and any(ready_image(p,image) for p in active),'image_id')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'image_id'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_6]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-100; then printf '%s\n' 'board:8080 = north-100: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
