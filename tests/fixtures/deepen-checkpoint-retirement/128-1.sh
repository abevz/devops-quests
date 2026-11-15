set -euo pipefail
cd ~/quest
kubectl exec -i deployment/ledger -- tar xf - -C /data < ledger.tar
