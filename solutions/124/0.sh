set -euo pipefail
cd ~/quest
volume=$(jq -r .volume /run/dq/facts/0/volume-contract.json)
kubectl patch pv "$volume" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
