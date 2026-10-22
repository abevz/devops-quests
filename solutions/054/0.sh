set -euo pipefail
cd ~/quest
cat > patch-4cf3f622c706.json <<'DQ_ASSET'
{
  "operation": {
    "sync": {}
  }
}
DQ_ASSET
jq -e . patch-4cf3f622c706.json >/dev/null
kubectl patch application station --type=merge --patch-file=patch-4cf3f622c706.json
for _ in $(seq 1 90); do
 if kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 2
done
kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
kubectl rollout status deployment/relay --timeout=90s
