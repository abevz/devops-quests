set -euo pipefail
cd ~/quest
source platform.env
source webhook.env
GITEA_API="${GIT_URL%/rail/station.git}/api/v1/repos/rail/station"
hook=$(cat /run/dq/facts/0/hook-id)
jq -n --arg url "$(jq -er .url /run/dq/facts/0/webhook-target.json)" --arg secret "$WEBHOOK_SECRET" '{config:{url:$url,content_type:"json",secret:$secret},events:["push"],branch_filter:"main",active:true}' > hook-repair.json
curl -fsS -u "$GIT_USER:$GIT_PASSWORD" -H 'Content-Type: application/json' --request PATCH --data-binary @hook-repair.json "$GITEA_API/hooks/$hook" >/dev/null
curl -fsS -u "$GIT_USER:$GIT_PASSWORD" --request POST "$GITEA_API/hooks/$hook/tests?ref=refs/heads/main" >/dev/null
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
