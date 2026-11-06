set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
kubectl get application station -o json | jq -e --arg repo "$GIT_URL" --arg ns "$DQ_NAMESPACE" '.spec.project=="station" and .spec.source.repoURL==$repo and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .spec.destination.namespace==$ns and .spec.destination.server=="https://kubernetes.default.svc"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
expected=$(git -C repository ls-remote origin refs/heads/main | cut -f1)
kubectl get application station -o json | jq -e --arg repo "$GIT_URL" --arg ns "$DQ_NAMESPACE" --arg rev "$expected" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -- wget -qO- http://127.0.0.1:8080)" = north-43
)
[ $? -eq 0 ] || failed=1
exit "$failed"
