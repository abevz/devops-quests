set -euo pipefail
cd ~/quest
cat > patch-6359124e73a6.json <<'DQ_ASSET'
[
  {
    "op": "remove",
    "path": "/spec/template/spec/nodeSelector"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/cpu",
    "value": "20m"
  }
]
DQ_ASSET
jq -e . patch-6359124e73a6.json >/dev/null
kubectl patch deployment relay --type=json --patch-file=patch-6359124e73a6.json
kubectl rollout status deployment/relay --timeout=90s
