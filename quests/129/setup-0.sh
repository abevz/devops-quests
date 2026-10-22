set -euo pipefail
cd ~/quest
kubectl delete configmap station --wait=false
