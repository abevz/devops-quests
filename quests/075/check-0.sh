set -euo pipefail
cd ~/quest
source platform.env
source webhook.env
GITEA_API="${GIT_URL%/rail/station.git}/api/v1/repos/rail/station"
hook=$(cat /run/dq/facts/0/hook-id)
curl -fsS -u "$GIT_USER:$GIT_PASSWORD" "$GITEA_API/hooks/$hook" | jq -e --arg url "$(jq -er .url /run/dq/facts/0/webhook-target.json)" '.active==true and .type=="gogs" and .config.url==$url and .config.content_type=="json" and .events==["push"] and .branch_filter=="main"' >/dev/null
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
test "$(cat release-commit)" != "$(cat /run/dq/facts/0/initial-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/initial-commit)" origin/main
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-75
source platform.env
jq -e --arg repo "${GIT_URL%.git}" '.repo==$repo and .branch=="main" and .authenticated==true' /run/dq/observations/webhook.json >/dev/null
