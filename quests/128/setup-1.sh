set -euo pipefail
cd ~/quest
kubectl scale deployment journal-writer --replicas=0
if test -n "$(kubectl get pods -l app=journal-writer -o name)"; then
 kubectl wait --for=delete pod -l app=journal-writer --timeout=90s
fi
set -euo pipefail
cd ~/quest
kubectl exec deployment/ledger -- sh -c 'printf "%s\n" damaged > /data/ledger.txt'
kubectl exec deployment/ledger -- sh -c 'printf damaged > /data/orders.tsv; rmdir /data/.checkpoint-lock 2>/dev/null || true'
kubectl exec deployment/summary -- sh -c 'printf damaged > /data/summary.json'
