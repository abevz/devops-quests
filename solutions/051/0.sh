set -euo pipefail
cd ~/quest
cat > patch-d2aefd87940b.json <<'DQ_ASSET'
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port",
    "value": 8080
  }
]
DQ_ASSET
jq -e . patch-d2aefd87940b.json >/dev/null
kubectl patch deployment relay --type=json --patch-file=patch-d2aefd87940b.json
kubectl rollout status deployment/relay --timeout=90s
