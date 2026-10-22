set -euo pipefail
cd ~/quest
kubectl exec deployment/ledger -- sh -c 'printf "%s\n" damaged > /data/ledger.txt'
