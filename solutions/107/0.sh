set -euo pipefail
cd ~/quest
source components.env
kubectl patch ingress board --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":8080}]'
for i in $(seq 1 30); do
 if test "$(kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: station.internal' "$INGRESS_URL" 2>/dev/null)" = north-107; then break; fi
 sleep 1
done
