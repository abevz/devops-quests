set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
test "$(kubectl auth can-i patch secret/station-repository -n "$ARGO_NAMESPACE")" = yes
test "$(kubectl auth can-i list secrets -n "$ARGO_NAMESPACE")" = no
test "$(kubectl auth can-i patch secret/unrelated -n "$ARGO_NAMESPACE")" = no
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl -n "$ARGO_NAMESPACE" get secret station-repository -o json | jq -e --arg password "$GIT_PASSWORD" '(.data.password|@base64d)==$password' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; .spec.source.repoURL==$url and (.spec.source.path | same_dir("manifests")) and .spec.source.targetRevision=="main"' >/dev/null
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
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-61
)
[ $? -eq 0 ] || failed=1
exit "$failed"
