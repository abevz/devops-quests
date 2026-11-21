set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
source webhook.env
GITEA_API="${GIT_URL%/rail/station.git}/api/v1/repos/rail/station"
hook=$(cat /run/dq/facts/0/hook-id)
curl -fsS -u "$GIT_USER:$GIT_PASSWORD" "$GITEA_API/hooks/$hook" | jq -e --arg url "$(jq -er .url /run/dq/facts/0/webhook-target.json)" '.active==true and .type=="gogs" and (.config.url | sub("\\?$";""))==$url and .config.content_type=="json" and .events==["push"] and .branch_filter=="main"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
test "$(cat release-commit)" != "$(cat /run/dq/facts/0/initial-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/initial-commit)" origin/main
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg url "$GIT_URL" 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; .spec.source.repoURL==$url and (.spec.source.path | same_dir("manifests")) and .spec.source.targetRevision=="main"' >/dev/null
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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY'
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-75
DQ_LEGACY
)
[ $? -eq 0 ] || dq_failed=1
(
set -euo pipefail
timeout --kill-after=1s 14s bash -euo pipefail <<'DQ_CURRENT'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_WEBHOOK_PUBLICATION'

import json,subprocess,yaml
from pathlib import Path
from dq_check import current_pods,pod_worker,ready_image,workload_worker
def k(*args):
 return json.loads(subprocess.check_output(['kubectl',*args,'-o','json'],timeout=2))
contract=json.loads(Path('/run/dq/facts/0/webhook-publication.json').read_text())
old=contract['deployment']
deployment=k('get','deployment','board')
assert deployment['metadata']['uid']==old['metadata']['uid']
assert deployment['spec']['selector']==old['spec']['selector']
assert deployment['spec']['replicas']==old['spec']['replicas']==1
assert deployment['spec']['template']['spec']==old['spec']['template']['spec']
app=k('get','application','board')
assert app['metadata']['uid']==contract['application']['metadata']['uid']
assert app['spec']==contract['application']['spec']
revision=app['status']['sync']['revision']
subprocess.run(['git','-C','repository','merge-base','--is-ancestor',contract['release_commit'],revision],check=True,timeout=2)
desired=yaml.safe_load(subprocess.check_output(['git','-C','repository','show',revision+':'+contract['source_file']],text=True,timeout=2))
assert desired['kind']=='ConfigMap' and desired['metadata']['name']==contract['approved']['metadata']['name']
assert desired['data']==contract['approved']['data']
config=k('get','configmap',desired['metadata']['name'])
assert config['metadata']['uid']==contract['publication_uid']
assert config['data']==desired['data']
worker=workload_worker(deployment)
pods=current_pods(deployment,k('get','replicasets'),k('get','pods'))
assert len(pods)==1
for pod in pods:
 assert ready_image(pod,worker['image'])
 current=pod_worker(pod)
 for key in ('command','args'):
  assert current.get(key)==worker.get(key)
 for mount in worker.get('volumeMounts',[]):
  assert mount.get('readOnly') is True and mount in current.get('volumeMounts',[])
 value=subprocess.check_output(['kubectl','exec',pod['metadata']['name'],'-c','worker','--','wget','-qO-','-T','2','http://127.0.0.1:8080'],timeout=3)
 assert value.decode().rstrip('\n')==desired['data']['notice'].rstrip('\n')

DQ_WEBHOOK_PUBLICATION

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

DQ_CURRENT
)
[ $? -eq 0 ] || dq_failed=1
set -e
test "$dq_failed" -eq 0
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
(
set -e
source platform.env
jq -e --arg repo "${GIT_URL%.git}" '.repo==$repo and .branch=="main" and .authenticated==true' /run/dq/observations/webhook.json >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
