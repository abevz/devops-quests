set -euo pipefail
cd ~/quest
cat > patch-0494dd09cd92.json <<'DQ_ASSET'
{
  "spec": {
    "selector": {
      "app": "relay"
    }
  }
}
DQ_ASSET
jq -e . patch-0494dd09cd92.json >/dev/null
kubectl patch service arrivals --type=merge --patch-file=patch-0494dd09cd92.json
