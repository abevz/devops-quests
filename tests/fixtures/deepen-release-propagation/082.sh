set -euo pipefail
cd ~/quest
helm upgrade board ./chart --set port=8080
kubectl rollout status deployment/relay --timeout=90s
for i in $(seq 1 30); do
 if test "$(kubectl exec deployment/relay -- wget -qO- -T 3 http://127.0.0.1:8080)" = signalrail; then break; fi
 sleep 1
done
test "$(kubectl exec deployment/relay -- wget -qO- -T 3 http://127.0.0.1:8080)" = signalrail
