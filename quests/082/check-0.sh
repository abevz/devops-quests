set -euo pipefail
cd ~/quest
kubectl rollout status deployment/relay --timeout=3s >/dev/null
helm status board -o json | jq -e '.info.status=="deployed"' >/dev/null
helm get values board --all -o json | jq -e '(.port|tostring)=="8080"' >/dev/null
test "$(kubectl exec deployment/relay -- wget -qO- -T 3 http://127.0.0.1:8080)" = signalrail
