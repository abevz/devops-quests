set -euo pipefail
cd ~/quest
cat > patch-95700f4a5070.json <<'DQ_ASSET'
{
  "data": {
    "route": "north"
  }
}
DQ_ASSET
jq -e . patch-95700f4a5070.json >/dev/null
kubectl patch configmap dispatch --type=merge --patch-file=patch-95700f4a5070.json
kubectl rollout restart deployment/relay
kubectl rollout status deployment/relay --timeout=90s
