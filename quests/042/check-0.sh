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

def argument(value):
    if value.startswith('/dev/fd/'):
        with open(value,encoding='utf-8',newline='') as stream:return stream.read().removesuffix('\n')
    return value
sys.argv=[sys.argv[0]]+[argument(value) for value in sys.argv[1:]]

def named(items,name):
    found=[item for item in items or [] if isinstance(item,dict) and item.get('name')==name]
    if len(found)!=1:raise ValueError('application container identity')
    return found[0]

def template_worker(deployment):
    return named(deployment['spec']['template']['spec']['containers'],'worker')

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

def ready_image_raw(pod,image):
    worker=pod_worker(pod);status=named(pod.get('status',{}).get('containerStatuses',[]),'worker')
    digest=image.rsplit('@',1)[-1]
    actual=re.search(r'(?:^|[@/])(sha256:[0-9a-f]{64})$',status.get('imageID',''))
    return pod.get('status',{}).get('phase')=='Running' and worker.get('image')==image and status.get('ready') is True and isinstance(status.get('state',{}).get('running'),dict) and re.fullmatch(r'sha256:[0-9a-f]{64}',digest) is not None and actual is not None and actual.group(1)==digest

def ready_image(pod,image):
    try:return ready_image_raw(pod,image)
    except Exception:return False

def unique_object(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('duplicate credential field')
        result[key]=value
    return result

def credentials(secret,registry,user,password):
    kind=secret.get('type')
    key='.dockerconfigjson' if kind=='kubernetes.io/dockerconfigjson' else '.dockercfg' if kind=='kubernetes.io/dockercfg' else None
    if key is None:return False
    value=json.loads(base64.b64decode(secret['data'][key],validate=True),object_pairs_hook=unique_object)
    auths=value.get('auths') if key=='.dockerconfigjson' else value
    if not isinstance(auths,dict):return False
    entry=auths.get(registry)
    if not isinstance(entry,dict):return False
    auth=entry.get('auth')
    if auth not in (None,''):
        return isinstance(auth,str) and base64.b64decode(auth.replace('\r','').replace('\n',''),validate=True)==(user+':'+password).encode()
    return entry.get('username')==user and entry.get('password')==password

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

def argument(value):
    if value.startswith('/dev/fd/'):
        with open(value,encoding='utf-8',newline='') as stream:return stream.read().removesuffix('\n')
    return value
sys.argv=[sys.argv[0]]+[argument(value) for value in sys.argv[1:]]

def named(items,name):
    found=[item for item in items or [] if isinstance(item,dict) and item.get('name')==name]
    if len(found)!=1:raise ValueError('application container identity')
    return found[0]

def template_worker(deployment):
    return named(deployment['spec']['template']['spec']['containers'],'worker')

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

def ready_image_raw(pod,image):
    worker=pod_worker(pod);status=named(pod.get('status',{}).get('containerStatuses',[]),'worker')
    digest=image.rsplit('@',1)[-1]
    actual=re.search(r'(?:^|[@/])(sha256:[0-9a-f]{64})$',status.get('imageID',''))
    return pod.get('status',{}).get('phase')=='Running' and worker.get('image')==image and status.get('ready') is True and isinstance(status.get('state',{}).get('running'),dict) and re.fullmatch(r'sha256:[0-9a-f]{64}',digest) is not None and actual is not None and actual.group(1)==digest

def ready_image(pod,image):
    try:return ready_image_raw(pod,image)
    except Exception:return False

def unique_object(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('duplicate credential field')
        result[key]=value
    return result

def credentials(secret,registry,user,password):
    kind=secret.get('type')
    key='.dockerconfigjson' if kind=='kubernetes.io/dockerconfigjson' else '.dockercfg' if kind=='kubernetes.io/dockercfg' else None
    if key is None:return False
    value=json.loads(base64.b64decode(secret['data'][key],validate=True),object_pairs_hook=unique_object)
    auths=value.get('auths') if key=='.dockerconfigjson' else value
    if not isinstance(auths,dict):return False
    entry=auths.get(registry)
    if not isinstance(entry,dict):return False
    auth=entry.get('auth')
    if auth not in (None,''):
        return isinstance(auth,str) and base64.b64decode(auth.replace('\r','').replace('\n',''),validate=True)==(user+':'+password).encode()
    return entry.get('username')==user and entry.get('password')==password

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
