set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    document=json.loads(subprocess.check_output(['tofu','show','-json'],stderr=subprocess.DEVNULL,timeout=5))
    pending=[document['values']['root_module']];found=False
    while pending:
        module=pending.pop();pending.extend(module.get('child_modules',[]))
        for resource in module.get('resources',[]):
            value=resource.get('values',{});filename=value.get('filename')
            if resource.get('mode')=='managed' and resource.get('type')=='local_file' and isinstance(filename,str):
                try:found=found or Path(filename).samefile('release.txt')
                except OSError:pass
    require(found,'state')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'state'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
facts=/run/dq/facts/0/recovery-contract.json
archive_hash=$(sha256sum recovery/checkpoint.tfstate 2>/dev/null | cut -d ' ' -f 1 || true)
if ! test -n "$archive_hash" || ! test "$archive_hash" = "$(jq -er .sha256 "$facts" 2>/dev/null || true)"; then
  printf '%s\n' 'Trusted checkpoint contents changed: ✗ [DQ:checkpoint_digest]'
  exit 1
fi
state=$(timeout 5s tofu state pull 2>/dev/null || true)
release_id=$(jq -er .release_id "$facts" 2>/dev/null || true)
handover_id=$(jq -er .handover_id "$facts" 2>/dev/null || true)
lineage=$(jq -er .lineage "$facts" 2>/dev/null || true)
record_matches() {
  jq -e --arg name "$1" --arg id "$2" '
    any(.resources[]?; .mode=="managed" and .type=="terraform_data" and
        (.module // "")=="" and .name==$name and
        (.instances | length)==1 and .instances[0].attributes.id==$id)
  ' <<<"$state" >/dev/null 2>&1
}
failed=0
if ! test -n "$lineage" || ! jq -e --arg lineage "$lineage" '.lineage==$lineage' <<<"$state" >/dev/null 2>&1 ||
   ! test -n "$handover_id" || ! record_matches handover "$handover_id"; then
  printf '%s\n' 'The newer handover binding or active lineage was lost: ✗ [DQ:handover_state]'
  failed=1
fi
if ! test -n "$release_id" || ! record_matches release_record "$release_id"; then
  printf '%s\n' 'Release binding differs from the trusted checkpoint: ✗ [DQ:checkpoint_binding]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(cat release.txt 2>/dev/null)" = release-90; then
  printf '%s\n' 'release.txt = release-90: ✗ [DQ:file]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:plan]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
