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
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 "$PRIVATE_IMAGE" "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$document" 4<<<"$replicasets" 5<<<"$pods" <<'DQ_PRIVATE_DECLARED_ONLY'
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

from dq_check import credential_fields as unique_object

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
    failed=False
    for marker,good in [('image',worker.get('image')==image and all(pod_worker(pod).get('image')==image for pod in active)),('policy',worker.get('imagePullPolicy')=='Always' and all(pod_worker(pod).get('imagePullPolicy')=='Always' for pod in active)),('secrets',bool(active) and all(pull_names(pod)=={'registry-pull'} for pod in active))]:
        if not good:print(f'Private application contract: ✗ [DQ:{marker}]');failed=True
    assert not failed
except Exception:
    sys.exit(1)
DQ_PRIVATE_DECLARED_ONLY
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
source platform.env
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
board=$(kubectl get deployment board -o json 2>/dev/null || true)
failed=0
check 'deployment/board replicas = 1 [DQ:replicas]' '.spec.replicas==1' "$board"
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
source platform.env
secret=$(kubectl get secret registry-pull -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$secret" <<'DQ_REGISTRY_CREDENTIALS'
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

from dq_check import credential_fields as unique_object

from dq_check import registry_credentials as credentials

def valid_secret(name,registry,user,password):
    try:return credentials(secret(name),registry,user,password)
    except Exception:return False

def secret(name):
    if not re.fullmatch(r'[a-z0-9](?:[-a-z0-9.]*[a-z0-9])?',name):raise ValueError('credential name')
    return json.loads(subprocess.check_output(['kubectl','get','secret',name,'-o','json'],stderr=subprocess.DEVNULL,timeout=2))
try:
    value=json.loads(sys.argv[1]);registry,user,password=sys.argv[2:5]
    if value.get('type') not in ('kubernetes.io/dockerconfigjson','kubernetes.io/dockercfg'):
        print('Usable registry credential Secret type: ✗ [DQ:secret_type]');sys.exit(1)
    key='.dockerconfigjson' if value['type']=='kubernetes.io/dockerconfigjson' else '.dockercfg'
    try:
        config=json.loads(base64.b64decode(value['data'][key],validate=True),object_pairs_hook=unique_object)
    except Exception:
        print('Usable registry credential payload: ✗ [DQ:outer]');sys.exit(1)
    try:
        auths=config['auths'] if key=='.dockerconfigjson' else config
        entry=auths[registry];auth=entry.get('auth')
        if auth not in (None,''):
            assert isinstance(auth,str)
            decoded=base64.b64decode(auth.replace('\r','').replace('\n',''),validate=True)
            assert b':' in decoded
        else:
            assert isinstance(entry.get('username'),str) and isinstance(entry.get('password'),str)
    except Exception:
        print('Usable registry authentication data: ✗ [DQ:auth]');sys.exit(1)
    if not credentials(value,registry,user,password):
        print('Registry credentials match the supplied environment: ✗ [DQ:credentials]');sys.exit(1)
except Exception:
    print('Usable registry authentication data: ✗ [DQ:auth]');sys.exit(1)
DQ_REGISTRY_CREDENTIALS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! kubectl rollout status deployment/board --timeout=3s >/dev/null 2>&1; then printf '%s\n' 'deployment/board rollout complete: ✗ [DQ:rollout]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://127.0.0.1:8080 2>/dev/null)" = north-42; then printf '%s\n' 'board Pod localhost:8080 = north-42: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
