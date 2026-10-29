set -euo pipefail
cd ~/quest
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
status=$(curl -fsS "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null || true)
if ! jq -e '.initialized == true' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status initialized = true: ✗'
  failed=1
fi
if ! jq -e '.sealed == false' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status sealed = false: ✗'
  failed=1
fi
if ! jq -e '.t == 2' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status t = 2: ✗'
  failed=1
fi
if ! jq -e '.n == 3' <<<"$status" >/dev/null 2>&1; then
  printf '%s\n' 'sys/seal-status n = 3: ✗'
  failed=1
fi
if ! test "$(stat -c %a unseal-shares.json 2>/dev/null)" = 600; then
  printf '%s\n' 'unseal-shares.json mode = 0600: ✗'
  failed=1
fi
if ! jq -e 'type == "array"' unseal-shares.json >/dev/null 2>&1; then
  printf '%s\n' 'unseal-shares.json type = array: ✗'
  failed=1
fi
if ! jq -e 'type == "array" and length == 2' unseal-shares.json >/dev/null 2>&1; then
  printf '%s\n' 'unseal-shares.json length = 2: ✗'
  failed=1
fi
if ! jq -e 'type == "array" and all(.[];type == "string")' unseal-shares.json >/dev/null 2>&1; then
  printf '%s\n' 'unseal-shares.json entries type = string: ✗'
  failed=1
fi
if ! jq -e 'type == "array" and length == 2 and .[0] != .[1]' unseal-shares.json >/dev/null 2>&1; then
  printf '%s\n' 'unseal-shares.json [0] ≠ [1]: ✗'
  failed=1
fi
if ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then
  printf '%s\n' 'reader secret/data/dispatch value = north-secret: ✗'
  failed=1
fi
exit "$failed"
