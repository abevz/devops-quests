set -euo pipefail
cd ~/quest
printf '%s
' '{"action":"restore-path"}' > webhook-repair.json
for i in $(seq 1 30); do
 if kubectl get validatingwebhookconfiguration "dq-webhook-${DQ_NAMESPACE#dq-}" -o json | jq -e '.webhooks[0].clientConfig.url|endswith("/validate")' >/dev/null; then break; fi
 sleep 1
done
jq '.data.route="north-121"' route.json > /tmp/fixed-route.json
cp /tmp/fixed-route.json route.json
kubectl apply -f route.json
kubectl rollout status deployment/board --timeout=90s
