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
revision=$(cat release-commit 2>/dev/null || true)
app=$(kubectl get application board -o json 2>/dev/null || true)
check_app() { local label=$1 expression=$2; if ! jq -e --arg url "$GIT_URL" --arg revision "$revision" "$expression" <<<"$app" >/dev/null 2>&1; then printf '%s\n' "application/board $label: ✗"; failed=1; fi; }
check_app 'repoURL = GIT_URL [DQ:repo]' '.spec.source.repoURL==$url'
check_app 'source path = manifests [DQ:path]' '(.spec.source.path | (startswith("/")|not) and ([splits("/") | select(.!="" and .!=".")]==["manifests"]))'
check_app 'targetRevision = main [DQ:target]' '.spec.source.targetRevision=="main"'
check_app 'sync status = Synced [DQ:synced]' '.status.sync.status=="Synced"'
if ! test -n "$revision"; then printf '%s\n' 'expected Git revision exists: ✗ [DQ:revision_exists]'; failed=1; fi
check_app 'sync revision = expected revision [DQ:revision]' '.status.sync.revision==$revision'
check_app 'selfHeal = true [DQ:selfheal]' '.spec.syncPolicy.automated.selfHeal==true'
check_app 'health = Healthy [DQ:health]' '.status.health.status=="Healthy"'
check_app 'prune = true [DQ:prune]' '.spec.syncPolicy.automated.prune==true'
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
revision=$(cat release-commit 2>/dev/null || true)
if ! git -C repository fetch origin main >/dev/null 2>&1; then printf '%s\n' 'git fetch origin main: ✗ [DQ:fetch]'; failed=1; fi
if ! test -n "$revision" || ! test "$(git -C repository rev-parse origin/main 2>/dev/null)" = "$revision"; then printf '%s\n' 'origin/main = release-commit: ✗ [DQ:origin]'; failed=1; fi
baseline=$(cat /run/dq/facts/0/baseline-commit 2>/dev/null || true)
if ! test -n "$revision" || ! test -n "$baseline" || test "$revision" = "$baseline"; then printf '%s\n' 'release-commit differs from baseline-commit: ✗ [DQ:changed]'; failed=1; fi
if ! test -n "$baseline" || ! git -C repository merge-base --is-ancestor "$baseline" origin/main >/dev/null 2>&1; then printf '%s\n' 'baseline-commit is ancestor of origin/main: ✗ [DQ:ancestor]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
source platform.env
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

try:
    image=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image']
    import yaml
    subprocess.check_call(['git','-C','repository','fetch','origin','main'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=8)
    d=yaml.safe_load(subprocess.check_output(['git','-C','repository','show','origin/main:manifests/board.yaml'],stderr=subprocess.DEVNULL,timeout=4));require(d.get('kind')=='Deployment' and d.get('metadata',{}).get('name')=='board','git_image');w=worker(d)
    require(w.get('image')==image,'git_image')
    require(w.get('imagePullPolicy')=='Always','git_policy')
    names={x.get('name') for x in d['spec']['template']['spec'].get('imagePullSecrets',[])}
    if not names:
        sa=d['spec']['template']['spec'].get('serviceAccountName') or 'default';names={x.get('name') for x in get('serviceaccount',sa).get('imagePullSecrets',[])}
    require(names=={'registry-pull'},'git_secrets')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'git_image'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
(
set -e
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

try:
    image=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image']
    d=get('deployment','board');w=worker(d)
    require(w.get('image')==image,'live_image')
    require(w.get('imagePullPolicy')=='Always','live_policy')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'live_image'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
if ! kubectl rollout status deployment/board --timeout=3s >/dev/null 2>&1; then printf '%s\n' 'deployment/board rollout complete: ✗ [DQ:rollout]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
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

def ready_image_raw(pod,image):
    worker=pod_worker(pod);status=named(pod.get('status',{}).get('containerStatuses',[]),'worker')
    digest=image.rsplit('@',1)[-1]
    actual=re.search(r'(?:^|[@/])(sha256:[0-9a-f]{64})$',status.get('imageID',''))
    return pod.get('status',{}).get('phase')=='Running' and worker.get('image')==image and status.get('ready') is True and isinstance(status.get('state',{}).get('running'),dict) and re.fullmatch(r'sha256:[0-9a-f]{64}',digest) is not None and actual is not None and actual.group(1)==digest

def ready_image(pod,image):
    try:return ready_image_raw(pod,image)
    except Exception:return False

try:
    d=get('deployment','board');w=worker(d);active=current_pods(d,get('replicasets'),get('pods'))
    image=json.loads(Path('/run/dq/facts/0/private-release.json').read_text())['image']
    require(w.get('image')==image and any(ready_image(p,image) for p in active),'image_id')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'image_id'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
image=$(jq -r '.image // ""' /run/dq/facts/0/private-release.json 2>/dev/null || true)
digest=${image##*@}
if ! test -n "$image"; then printf '%s\n' 'private-release.json image exists: ✗ [DQ:release_image]'; failed=1; fi
umask 077
config=$(mktemp)
trap 'rm -f "$config"' EXIT
printf 'user = "%s:%s"\n' "$REGISTRY_USER" "$REGISTRY_PASSWORD" > "$config"
if ! test -n "$image" || ! curl -fsS --max-time 4 --config "$config" --cacert registry-ca.crt -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" >/dev/null 2>&1; then printf '%s\n' 'authenticated registry serves frozen digest: ✗ [DQ:registry]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-80; then printf '%s\n' 'board:8080 = north-80: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
