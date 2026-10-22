set -euo pipefail
cd ~/quest
cat > patch-81f8b28bebaa.json <<'DQ_ASSET'
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port",
    "value": 8080
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path",
    "value": "/"
  }
]
DQ_ASSET
jq -e . patch-81f8b28bebaa.json >/dev/null
kubectl patch deployment relay --type=json --patch-file=patch-81f8b28bebaa.json
kubectl rollout status deployment/relay --timeout=90s
