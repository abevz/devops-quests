set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$headers/manager"
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
if ! curl -fsS -H @"$headers/manager" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" 2>/dev/null | jq -er .data.policy > observed-reader.hcl 2>/dev/null; then
  printf '%s\n' 'rail-reader policy read: ✗ [DQ:policy_read]'
  failed=1
fi

if ! python3 -I - <<'ACL_SCOPE'
import json,re,sys
from pathlib import Path
text=Path('observed-reader.hcl').read_text()
def unique_object(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('duplicate policy field')
        result[key]=value
    return result
try:
    value=json.loads(text,object_pairs_hook=unique_object)
except json.JSONDecodeError:
    value=None
except ValueError:
    sys.exit(1)
if value is not None:
    if not isinstance(value,dict) or set(value)!={'path'}:sys.exit(1)
    paths=value['path']
    if not isinstance(paths,dict) or set(paths)!={'secret/data/dispatch'}:sys.exit(1)
    rule=paths['secret/data/dispatch']
    constraints={'allowed_parameters','denied_parameters','required_parameters','min_wrapping_ttl','max_wrapping_ttl'}
    if not isinstance(rule,dict) or not set(rule)<={'capabilities'}|constraints:sys.exit(1)
    capabilities=rule.get('capabilities')
    ok=isinstance(capabilities,list) and bool(capabilities) and all(item=='read' for item in capabilities)
else:
    text=re.sub(r'/\*.*?\*/','',text,flags=re.S)
    text=re.sub(r'(?m)(#|//).*$','',text)
    block=r'path\s+"secret/data/dispatch"\s*\{\s*capabilities\s*=\s*\[\s*"read"(?:\s*,\s*"read")*\s*,?\s*\]\s*\}'
    ok=re.fullmatch(r'\s*(?:'+block+r'\s*)+',text) is not None
sys.exit(0 if ok else 1)
ACL_SCOPE
then
  printf '%s\n' 'rail-reader policy: secret/data/dispatch [read] only: ✗ [DQ:policy_scope]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$headers/manager"
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
if ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then
  printf '%s\n' 'VAULT_READER_TOKEN secret/data/dispatch value = north-secret: ✗ [DQ:reader]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
umask 077
headers=$(mktemp -d)
trap 'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"' EXIT
printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$headers/manager"
printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$headers/reader"
failed=0
cat > capability-paths.json <<'DQ_ASSET'
{"paths": ["secret/data/dispatch", "secret/data/wrong", "secret/data/other", "sys/mounts"]}
DQ_ASSET
capabilities=$(curl -fsS -X POST -H @"$headers/reader" -H 'Content-Type: application/json' --data-binary @capability-paths.json "$VAULT_ADDR/v1/sys/capabilities-self" 2>/dev/null || true)
for path in secret/data/dispatch secret/data/wrong secret/data/other sys/mounts; do
  expected=deny
  if test "$path" = secret/data/dispatch; then expected=read; fi
  if ! jq -e --arg path "$path" --arg expected "$expected" '(.data // .)[$path] == [$expected]' <<<"$capabilities" >/dev/null 2>&1; then
    printf '%s\n' "capabilities-self $path = [$expected]: ✗ [DQ:cap_${path//\//_}]"
    failed=1
  fi
done
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
