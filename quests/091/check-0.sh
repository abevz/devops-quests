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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
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
    assert worker.get('image')==image and any(ready_image(pod,image) for pod in active)
except Exception:
    sys.exit(1)
DQ_PRIVATE_IMAGE
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
