set -euo pipefail
cd ~/quest
source platform.env
test "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret
test "$(kubectl get secret route-secret -o jsonpath='{.data.value}' | base64 -d)" = north-secret
test "$(kubectl exec deployment/relay -- printenv ROUTE_SECRET)" = north-secret
kubectl rollout status deployment/relay --timeout=3s >/dev/null
