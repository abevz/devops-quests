set -euo pipefail
cd ~/quest
cat > patch-0b1e1268cddb.json <<'DQ_ASSET'
{
  "spec": {
    "minAvailable": 1
  }
}
DQ_ASSET
jq -e . patch-0b1e1268cddb.json >/dev/null
kubectl patch pdb relay --type=merge --patch-file=patch-0b1e1268cddb.json
sleep 3
