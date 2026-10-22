set -euo pipefail
cd ~/quest
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-95
healthy=$(cat /run/dq/facts/0/healthy-commit)
faulty=$(cat /run/dq/facts/0/faulty-commit)
test "$(cat release-commit)" != "$faulty"
git -C repository merge-base --is-ancestor "$faulty" origin/main
test "$(git -C repository show origin/main:manifests/board.json | sha256sum)" = "$(git -C repository show "$healthy:manifests/board.json" | sha256sum)"
