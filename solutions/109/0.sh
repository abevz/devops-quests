set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/securityContext", "value": {"privileged": false, "allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}, "readOnlyRootFilesystem": true}}]'
kubectl rollout status deployment/board --timeout=90s
