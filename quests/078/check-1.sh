set -euo pipefail
cd ~/quest
failed=0
set +e
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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
source platform.env
image=$(jq -er .image /run/dq/facts/0/registry-target.json)
source platform.env
document=$(kubectl get deployment board -o json 2>/dev/null || true)
replicasets=$(kubectl get replicasets -o json 2>/dev/null || true)
pods=$(kubectl get pods -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 "$image" "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$document" 4<<<"$replicasets" 5<<<"$pods" <<'DQ_PRIVATE_IMAGE_POLICY'
import base64,json,os,re,subprocess,sys

from dq_check import read_argument as argument
sys.argv=[sys.argv[0]]+[argument(value) for value in sys.argv[1:]]

from dq_check import named

from dq_check import workload_worker as _dq_worker

def template_worker(document):
    return _dq_worker(document, error="application container identity", ignore_non_mappings=True)

from dq_check import current_pods

from dq_check import pod_worker
from dq_check import pull_secret_names as pull_names



from dq_check import ready_image


from dq_check import registry_credentials as credentials

def valid_secret(name,registry,user,password):
    try:return credentials(secret(name),registry,user,password)
    except Exception:return False

def secret(name):
    if not re.fullmatch(r'[a-z0-9](?:[-a-z0-9.]*[a-z0-9])?',name):raise ValueError('credential name')
    return json.loads(subprocess.check_output(['kubectl','get','secret',name,'-o','json'],stderr=subprocess.DEVNULL,timeout=2))

try:
    deployment,replicasets,pods=[json.loads(value) for value in sys.argv[1:4]]
    image,registry,user,password=sys.argv[4:8]
    worker=template_worker(deployment)
    active=current_pods(deployment,replicasets,pods)
    assert worker.get('image')==image and worker.get('imagePullPolicy')=='Always'
    assert any(ready_image(pod,image) and pod_worker(pod).get('imagePullPolicy')=='Always' and bool(pull_names(pod)) for pod in active)
except Exception:
    sys.exit(1)
DQ_PRIVATE_IMAGE_POLICY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
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
source platform.env
python3 -I - <<'DQ_REGISTRY_CREDENTIAL'

import base64,hashlib,json,os,ssl,urllib.request
from pathlib import Path
source=json.loads(Path('/run/dq/facts/0/registry-source.json').read_text())
assert os.environ['REGISTRY']==source['endpoint']
assert os.environ['REGISTRY_USER']==source['username']
assert hashlib.sha256(os.environ['REGISTRY_PASSWORD'].encode()).hexdigest()==source['password_sha256']
assert hashlib.sha256(Path('registry-ca.crt').read_bytes()).hexdigest()==source['ca_sha256']
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):
  return None
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect(),
urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile='registry-ca.crt')))
headers={'Authorization':'Basic '+base64.b64encode((source['username']+':'+os.environ['REGISTRY_PASSWORD']).encode()).decode(),
'Accept':'application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'}
def manifest(reference):
 request=urllib.request.Request('https://'+source['endpoint']+'/v2/parcel/manifests/'+reference,headers=headers)
 with opener.open(request,timeout=2) as response:
  body=response.read(2097153)
  assert len(body)<=2097152
  digest='sha256:'+hashlib.sha256(body).hexdigest()
  assert response.headers.get('Docker-Content-Digest')==digest
  return digest

from dq_check import registry_credentials
import subprocess
contract=json.loads(Path('/run/dq/facts/0/registry-consumer.json').read_text())
target=json.loads(Path('/run/dq/facts/0/registry-target.json').read_text())
assert manifest(target['image'].split('@',1)[1])==target['image'].split('@',1)[1]
secret=json.loads(subprocess.check_output(['kubectl','get','secret',contract['secret_name'],'-o','json'],timeout=2))
assert secret['metadata']['uid']==contract['secret_uid']
assert registry_credentials(secret,source['endpoint'],source['username'],os.environ['REGISTRY_PASSWORD'])

DQ_REGISTRY_CREDENTIAL

) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_0]'
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
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0

)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
source platform.env
image=$(jq -er .image /run/dq/facts/0/registry-target.json)
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image and .spec.template.spec.containers[0].imagePullPolicy=="Always" and .spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' >/dev/null
digest=$(printf %s "$image" | cut -d@ -f2)
kubectl get pods -l app=board -o json | jq -e --arg digest "$digest" 'any(.items[];.metadata.deletionTimestamp==null and any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The declared private pull and live digest could not be verified: ✗ [DQ:registry_pull_policy]' >&2
  exit "$code"
fi
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
source platform.env
image=$(jq -er .image /run/dq/facts/0/registry-target.json)
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.replicas==1' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
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
source platform.env
python3 -I - <<'DQ_REGISTRY_PODS'

import json,subprocess
from pathlib import Path
from dq_check import current_pods,pod_worker,ready_image,workload_worker,pull_secret_names
def k(*args):
 return json.loads(subprocess.check_output(['kubectl',*args,'-o','json'],timeout=2))
contract=json.loads(Path('/run/dq/facts/0/registry-consumer.json').read_text())
old=contract['deployment']
deployment=k('get','deployment','board')
assert deployment['metadata']['uid']==old['metadata']['uid']
assert deployment['spec']['selector']==old['spec']['selector']
assert deployment['spec']['template']['spec']==old['spec']['template']['spec']
worker=workload_worker(deployment)
active=current_pods(deployment,k('get','replicasets'),k('get','pods'))
assert len(active)==1
for pod in active:
 assert ready_image(pod,worker['image'])
 assert pod_worker(pod).get('imagePullPolicy')=='Always'
 assert pull_secret_names(pod)=={contract['secret_name']}
 assert pod_worker(pod).get('command')==worker.get('command')
 assert pod_worker(pod).get('args')==worker.get('args')

DQ_REGISTRY_PODS

) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_2]'
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
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0

)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://127.0.0.1:8080)" = north-78
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The actual private image consumer response could not be verified: ✗ [DQ:registry_http]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
