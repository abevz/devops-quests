set -euo pipefail
cd ~/quest
test "$(tar tf ledger.tar)" = ledger.txt
test "$(tar xOf ledger.tar ledger.txt | sha256sum | awk '{print $1}')" = "$(cat /run/dq/facts/0/original-ledger.sha256)"
test "$(kubectl get pvc ledger -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-pvc-uid)"
