set -euo pipefail
cd ~/quest
kubectl get pdb relay -o json | jq -e '.status.currentHealthy>=2 and .status.disruptionsAllowed>=1 and .spec.minAvailable==1' >/dev/null
