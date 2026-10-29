set -euo pipefail
cd ~/quest
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$headers/manager"
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
if ! curl -fsS -H @"$headers/manager" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" 2>/dev/null | jq -er .data.policy > observed-reader.hcl 2>/dev/null; then
  printf '%s\n' 'rail-reader policy read: ✗'
  failed=1
fi
if ! python3 - <<'ACL_SCOPE'
import re
from pathlib import Path
p = Path('observed-reader.hcl').read_text()
p = re.sub(r'/\*.*?\*/', '', p, flags=re.S)
p = re.sub(r'(?m)(#|//).*$','',p)
block = r'path\s+"secret/data/dispatch"\s*\{\s*capabilities\s*=\s*\[\s*"read"\s*,?\s*\]\s*\}'
if not re.fullmatch(r'\s*(?:' + block + r'\s*)+', p):
    raise SystemExit(1)
ACL_SCOPE
then
  printf '%s\n' 'rail-reader policy: secret/data/dispatch [read] only: ✗'
  failed=1
fi
if ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then
  printf '%s\n' 'VAULT_READER_TOKEN secret/data/dispatch value = north-secret: ✗'
  failed=1
fi
cat > capability-paths.json <<'DQ_ASSET'
{"paths": ["secret/data/dispatch", "secret/data/wrong", "secret/data/other", "sys/mounts"]}
DQ_ASSET
capabilities=$(curl -fsS -X POST -H @"$headers/reader" -H 'Content-Type: application/json' --data-binary @capability-paths.json "$VAULT_ADDR/v1/sys/capabilities-self" 2>/dev/null || true)
for path in secret/data/dispatch secret/data/wrong secret/data/other sys/mounts; do
  expected=deny
  if test "$path" = secret/data/dispatch; then expected=read; fi
  if ! jq -e --arg path "$path" --arg expected "$expected" '(.data // .)[$path] == [$expected]' <<<"$capabilities" >/dev/null 2>&1; then
    printf '%s\n' "capabilities-self $path = [$expected]: ✗"
    failed=1
  fi
done
exit "$failed"
