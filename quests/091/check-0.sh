set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
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
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-91
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
image=$(jq -er .image /run/dq/facts/0/release-evidence.json)
commit=$(jq -er .commit /run/dq/facts/0/release-evidence.json)
test "$commit" != "$(cat release-commit)"
git -C repository merge-base --is-ancestor "$commit" origin/main
test "$(git -C repository show "$commit:site/index.html")" = north-91
jq -e --arg image "$image" --arg commit "$commit" --arg repo "$GIT_URL" '(keys==["commit","image","repo"]) and .image==$image and .commit==$commit and .repo==$repo' provenance.json >/dev/null
digest=${image##*@}
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" > /tmp/actual-manifest.json
test "sha256:$(sha256sum /tmp/actual-manifest.json | cut -d' ' -f1)" = "$digest"
config=$(jq -er .config.digest /tmp/actual-manifest.json)
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY/v2/parcel/blobs/$config" | jq -e --arg rev "$commit" '.config.Labels["org.opencontainers.image.revision"]==$rev' >/dev/null
source platform.env
document=$(kubectl get deployment board -o json 2>/dev/null || true)
replicasets=$(kubectl get replicasets -o json 2>/dev/null || true)
pods=$(kubectl get pods -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 "$image" "$REGISTRY" "$REGISTRY_USER" "$REGISTRY_PASSWORD" 3<<<"$document" 4<<<"$replicasets" 5<<<"$pods" <<'DQ_PRIVATE_IMAGE'
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
    assert worker.get('image')==image and any(ready_image(pod,image) for pod in active)
except Exception:
    sys.exit(1)
DQ_PRIVATE_IMAGE
)
[ $? -eq 0 ] || failed=1
exit "$failed"
