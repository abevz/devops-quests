set -euo pipefail
cd ~/quest
printf '%s
' '{"fault":"selector"}' > diagnosis.json
kubectl patch service board --type=json -p '[{"op": "replace", "path": "/spec/selector", "value": {"app": "board"}}]'
kubectl patch service board --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
for i in $(seq 1 30); do
 if test "$(kubectl exec deployment/client -- wget -qO- -T 2 http://board:8080)" = north-118; then exit 0; fi
 sleep 1
done
exit 1
