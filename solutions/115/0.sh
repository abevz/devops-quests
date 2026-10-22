set -euo pipefail
cd ~/quest
kubectl patch service board --type=json -p '[{"op": "replace", "path": "/spec/selector", "value": {"app": "green"}}]'
for i in $(seq 1 20); do
 if test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = green-115; then break; fi
 sleep 1
done
