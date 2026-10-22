set -euo pipefail
cd ~/quest
kubectl patch httproute board --type=json -p '[{"op": "replace", "path": "/spec/rules/0/backendRefs/0/port", "value": 8099}]'
kubectl patch networkpolicy board-ingress --type=json -p '[{"op": "replace", "path": "/spec/ingress/0/from/0/podSelector/matchLabels/app", "value": "retired-gateway"}]'
