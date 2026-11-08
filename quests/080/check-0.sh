set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
revision=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
app=$(kubectl get application board -o json 2>/dev/null || true)
check_app() { local label=$1 expression=$2; if ! jq -e --arg url "$GIT_URL" --arg revision "$revision" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check_app 'repoURL = GIT_URL [DQ:repo]' '.spec.source.repoURL==$url'
check_app 'source path = manifests [DQ:path]' '(.spec.source.path | (startswith("/")|not) and ([splits("/") | select(.!="" and .!=".")]==["manifests"]))'
check_app 'targetRevision = main [DQ:target]' '.spec.source.targetRevision=="main"'
check_app 'sync status = Synced [DQ:synced]' '.status.sync.status=="Synced"'
if ! test -n "$revision"; then printf '%s\n' 'expected Git revision exists: ✗ [DQ:revision_exists]'; failed=1; fi
check_app 'sync revision = expected revision [DQ:revision]' '.status.sync.revision==$revision'
check_app 'selfHeal = true [DQ:selfheal]' '.spec.syncPolicy.automated.selfHeal==true'
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

def named(items, name):
    found=[x for x in items or [] if isinstance(x,dict) and x.get('name')==name]
    if len(found)!=1:raise ValueError('named identity')
    return found[0]

def worker(document):return named(document['spec']['template']['spec']['containers'],'worker')

def require(good, marker):
    if not good:raise AssertionError(marker)

def current_pods(deployment,replicasets,pods):
    uid=deployment['metadata']['uid']
    if not isinstance(uid,str) or not uid:raise ValueError('deployment identity')
    owners={rs['metadata']['uid'] for rs in replicasets.get('items',[]) if any(ref.get('kind')=='Deployment' and ref.get('uid')==uid and ref.get('controller') is True for ref in rs.get('metadata',{}).get('ownerReferences',[]))}
    return [pod for pod in pods.get('items',[]) if pod.get('metadata',{}).get('deletionTimestamp') is None and pod.get('status',{}).get('phase') not in ('Failed','Succeeded') and any(ref.get('kind')=='ReplicaSet' and ref.get('uid') in owners and ref.get('controller') is True for ref in pod.get('metadata',{}).get('ownerReferences',[]))]

def pod_worker(pod):return named(pod.get('spec',{}).get('containers',[]),'worker')

def pull_names(pod):
    names=set()
    for entry in pod.get('spec',{}).get('imagePullSecrets') or []:
        value=entry.get('name')
        if not isinstance(value,str) or not re.fullmatch(r'[a-z0-9](?:[-a-z0-9.]*[a-z0-9])?',value):raise ValueError('pull credential identity')
        names.add(value)
    return names

try:
    d=get('deployment','board');w=worker(d);active=current_pods(d,get('replicasets'),get('pods'))
    require(w.get('imagePullPolicy')=='Always' and bool(active) and all(pod_worker(p).get('imagePullPolicy')=='Always' for p in active),'policy')
    require(all(pull_names(p)=={'registry-pull'} for p in active),'secrets')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'secrets'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
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
exit "$failed"
