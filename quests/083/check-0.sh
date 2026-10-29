set -euo pipefail
cd ~/quest
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
if ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then
  printf '%s\n' 'reader secret/data/dispatch value = north-secret: ✗'
  failed=1
fi
if ! test "$(kubectl get secret route-secret -o jsonpath='{.data.value}' 2>/dev/null | base64 -d 2>/dev/null)" = north-secret; then
  printf '%s\n' 'Secret route-secret value = north-secret: ✗'
  failed=1
fi
if ! test "$(kubectl exec deployment/relay -- printenv ROUTE_SECRET 2>/dev/null)" = north-secret; then
  printf '%s\n' 'deployment/relay ROUTE_SECRET = north-secret: ✗'
  failed=1
fi
if ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1; then
  printf '%s\n' 'deployment/relay rollout → 0: ✗'
  failed=1
fi
exit "$failed"
