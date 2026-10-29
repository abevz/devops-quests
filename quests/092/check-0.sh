set -euo pipefail
cd ~/quest
failed=0
if ! test -s /run/dq/facts/0/safe-state.sha256 || ! test "$(sha256sum safe-state.json 2>/dev/null | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/safe-state.sha256 2>/dev/null)"; then
  printf '%s\n' 'sha256(safe-state.json) = /run/dq/facts/0/safe-state.sha256: ✗ [DQ:condition_0]'
  failed=1
fi
if ! jq -e '.resources|any(.module=="module.north" and .type=="local_file" and .name=="ledger")' safe-state.json >/dev/null 2>&1; then
  printf '%s\n' 'safe-state.json ∋ module.north.local_file.ledger: ✗ [DQ:condition_1]'
  failed=1
fi
if ! test "$(tofu state list 2>/dev/null)" = module.station.local_file.ledger; then
  printf '%s\n' 'tofu state list = module.station.local_file.ledger: ✗ [DQ:condition_2]'
  failed=1
fi
if ! test -s /run/dq/facts/0/original-id || ! test "$(tofu output -raw ledger_id 2>/dev/null)" = "$(cat /run/dq/facts/0/original-id 2>/dev/null)"; then
  printf '%s\n' 'ledger_id = /run/dq/facts/0/original-id: ✗ [DQ:condition_3]'
  failed=1
fi
if ! test "$(cat ledger.txt 2>/dev/null)" = north-92; then
  printf '%s\n' 'ledger.txt = north-92: ✗ [DQ:condition_4]'
  failed=1
fi
if ! jq -e '(.resource_changes|length)==1' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json resource_changes length = 1: ✗ [DQ:condition_5]'
  failed=1
fi
if ! jq -e 'all(.resource_changes[];.change.actions==["no-op"])' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json resource_changes actions = ["no-op"]: ✗ [DQ:condition_6]'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_7]'
  failed=1
fi
exit "$failed"
