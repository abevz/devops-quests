set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
faulty=$(cat /run/dq/facts/0/faulty-commit)
test "$(cat release-commit)" != "$faulty"
git -C repository merge-base --is-ancestor "$faulty" origin/main
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main"' >/dev/null
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
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080)" = north-95
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
healthy=$(cat /run/dq/facts/0/healthy-commit)
test "$(git -C repository show origin/main:manifests/board.yaml | sha256sum)" = "$(git -C repository show "$healthy:manifests/board.yaml" | sha256sum)"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
