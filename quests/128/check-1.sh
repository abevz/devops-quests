set -euo pipefail
cd ~/quest
test "$(tar tf ledger.tar)" = ledger.txt
test "$(tar xOf ledger.tar ledger.txt | sha256sum | awk '{print $1}')" = "$(cat /run/dq/facts/0/original-ledger.sha256)"
test "$(kubectl get pvc ledger -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-pvc-uid)"
test "$(kubectl exec deployment/ledger -- sha256sum /data/ledger.txt | awk '{print $1}')" = "$(cat /run/dq/facts/0/original-ledger.sha256)"
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://ledger:8080/ledger.txt | sha256sum | awk '{print $1}')" = "$(cat /run/dq/facts/0/original-ledger.sha256)"
