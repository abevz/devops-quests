set -euo pipefail
cd ~/quest
kubectl patch daemonset relay --type=json -p '[{"op":"replace","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/os":"linux"}}]'
kubectl rollout status daemonset/relay --timeout=90s
