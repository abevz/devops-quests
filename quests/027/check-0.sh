set -euo pipefail
cd ~/quest
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
source platform.env
kubectl rollout status deployment/relay --timeout=3s >/dev/null
document=$(kubectl get deployment relay -o json 2>/dev/null || true)
replicasets=$(kubectl get replicasets -o json 2>/dev/null || true)
pods=$(kubectl get pods -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 "$PRIVATE_IMAGE" "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$document" 4<<<"$replicasets" 5<<<"$pods" <<'DQ_PRIVATE_PULL'
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
    assert active and all(pod_worker(pod).get('image')==image and pod_worker(pod).get('imagePullPolicy')=='Always' for pod in active)
    assert all(any(valid_secret(name,registry,user,password) for name in pull_names(pod)) for pod in active)
    assert any(ready_image(pod,image) for pod in active)
except Exception:
    sys.exit(1)
DQ_PRIVATE_PULL
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
