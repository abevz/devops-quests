set -euo pipefail
cd ~/quest
printf '%s
' '{"fault":"selector"}' > diagnosis.json
kubectl patch service board --type=json -p '[{"op": "replace", "path": "/spec/selector", "value": {"app": "board"}}]'
