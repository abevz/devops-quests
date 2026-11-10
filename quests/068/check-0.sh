set -euo pipefail
cd ~/quest
failed=0
set +e
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
kubectl get application board -o json | jq -e '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-68
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/baseline-commit)" origin/main
test "$(git -C repository rev-parse origin/main)" != "$(cat /run/dq/facts/0/baseline-commit)"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_GIT_HEALTH'
import json,re,subprocess,sys,yaml
from pathlib import Path
from decimal import Decimal

def execute(args):return subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=4)
def deployment(text):
    found=[]
    def visit(value,depth=0):
        if depth>64:raise ValueError('manifest nesting')
        if isinstance(value,list):
            for entry in value:visit(entry,depth+1)
        elif isinstance(value,dict):
            if value.get('kind')=='List':visit(value.get('items',[]),depth+1)
            elif value.get('kind')=='Deployment' and value.get('metadata',{}).get('name')=='board':found.append(value)
    for value in yaml.safe_load_all(text):visit(value)
    if len(found)!=1:raise ValueError('board Deployment identity')
    return found[0]
from dq_check import workload_worker as _dq_worker

def worker(document):
    return _dq_worker(document, error="application worker identity")
from dq_check import quantity as _dq_quantity

def quantity(value):
    return _dq_quantity(value, dialect='unicode_finite')

from dq_check import resource_subset as subset


from dq_check import health_probe as probe

from dq_check import env_values as env

from dq_check import workload_agreement as agreement

from dq_check import workload_safety as safety

try:
    desired=deployment(execute(['git','-C','repository','show','origin/main:manifests/board.yaml']))
    live=json.loads(execute(['kubectl','get','deployment','board','-o','json']))
    assert agreement(desired,live)
    execute(['kubectl','rollout','status','deployment/board','--timeout=3s'])
    assert execute(['timeout','4s','kubectl','exec','--pod-running-timeout=2s','deployment/board','-c','worker','--','wget','-qO-','-T','3','http://board:8080']).rstrip(b'\n')==b'north-68'
except Exception:
    sys.exit(1)
DQ_GIT_HEALTH
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_5]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
