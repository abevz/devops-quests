set -euo pipefail
cd ~/quest
source platform.env
test "$(kubectl auth can-i patch secret/station-repository -n "$ARGO_NAMESPACE")" = yes
test "$(kubectl auth can-i list secrets -n "$ARGO_NAMESPACE")" = no
test "$(kubectl auth can-i patch secret/unrelated -n "$ARGO_NAMESPACE")" = no
kubectl -n "$ARGO_NAMESPACE" get secret station-repository -o json | jq -e --arg password "$GIT_PASSWORD" '(.data.password|@base64d)==$password' >/dev/null
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-61
