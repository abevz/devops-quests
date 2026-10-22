set -euo pipefail
cd ~/quest
kubectl delete deployment board --wait=true --timeout=45s
kubectl delete pvc ledger --wait=true --timeout=45s
kubectl create -f claim.json
kubectl apply -f board.json
