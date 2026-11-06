set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl get application board -o json | jq -e '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-68
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/baseline-commit)" origin/main
test "$(git -C repository rev-parse origin/main)" != "$(cat /run/dq/facts/0/baseline-commit)"
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].readinessProbe.httpGet.port==8080' >/dev/null
git -C repository show origin/main:manifests/board.yaml | python3 -c 'import json,sys,yaml; json.dump(yaml.safe_load(sys.stdin),sys.stdout)' | jq -e '.spec.template.spec.containers[0].readinessProbe.httpGet.port==8080' >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
