set -euo pipefail
cd ~/quest
kubectl exec deployment/ledger -- tar cf - -C /data ledger.txt > ledger.tar
