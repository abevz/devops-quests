set -euo pipefail
cd ~/quest
kubectl patch pdb board-budget --type=merge -p '{"spec":{"minAvailable":1}}'
for i in $(seq 1 20); do
 if kubectl get pdb board-budget -o json | jq -e '.status.disruptionsAllowed==1' >/dev/null; then break; fi
 sleep 1
done
bash evict-one.sh
for i in $(seq 1 30); do
 if kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==2 and .status.disruptionsAllowed==1' >/dev/null; then break; fi
 sleep 1
done
