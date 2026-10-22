set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=merge -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl rollout undo deployment/board --to-revision="$(cat /run/dq/facts/0/healthy-revision)"
kubectl rollout status deployment/board --timeout=90s
