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
source platform.env
document=$(kubectl get deployment board -o json 2>/dev/null || true)
replicasets=$(kubectl get replicasets -o json 2>/dev/null || true)
pods=$(kubectl get pods -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 "$PRIVATE_IMAGE" "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$document" 4<<<"$replicasets" 5<<<"$pods" <<'DQ_PRIVATE_IMAGE'
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
    assert worker.get('image')==image and any(ready_image(pod,image) for pod in active)
except Exception:
    sys.exit(1)
DQ_PRIVATE_IMAGE
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
source platform.env
document=$(kubectl get deployment board -o json 2>/dev/null || true)
replicasets=$(kubectl get replicasets -o json 2>/dev/null || true)
pods=$(kubectl get pods -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 "$PRIVATE_IMAGE" "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$document" 4<<<"$replicasets" 5<<<"$pods" <<'DQ_PRIVATE_ONLY_AUTH'
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
    assert worker.get('imagePullPolicy')=='Always' and active
    assert all(pod_worker(pod).get('imagePullPolicy')=='Always' and pull_names(pod)=={'registry-pull'} for pod in active)
except Exception:
    sys.exit(1)
DQ_PRIVATE_ONLY_AUTH
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
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- http://127.0.0.1:8080)" = north-49
)
[ $? -eq 0 ] || failed=1
exit "$failed"
