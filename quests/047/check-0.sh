set -euo pipefail
cd ~/quest
failed=0
if ! test -s original-addresses || ! diff -q <(tofu state list 2>/dev/null | sort) <(sort original-addresses 2>/dev/null) >/dev/null 2>&1; then
  printf '%s\n' 'tofu state list = original-addresses: ✗'
  failed=1
fi
if ! tofu output -json ids 2>/dev/null | jq -e --slurpfile old original-ids.json '. == $old[0]' >/dev/null 2>&1; then
  printf '%s\n' 'tofu output -json ids = original-ids.json: ✗'
  failed=1
fi
if ! test "$(cat north.txt 2>/dev/null)" = north-47; then
  printf '%s\n' 'north.txt = north-47: ✗'
  failed=1
fi
if ! test "$(cat depot.txt 2>/dev/null)" = depot-47; then
  printf '%s\n' 'depot.txt = depot-47: ✗'
  failed=1
fi
if ! tofu output -json contracts 2>/dev/null | jq -e '.station.release==2' >/dev/null 2>&1; then
  printf '%s\n' 'contracts.station.release = 2: ✗'
  failed=1
fi
if ! tofu output -json contracts 2>/dev/null | jq -e --arg checksum "$(sha256sum north.txt 2>/dev/null | cut -d' ' -f1)" '.station.checksum==$checksum' >/dev/null 2>&1; then
  printf '%s\n' 'contracts.station.checksum = sha256(north.txt): ✗'
  failed=1
fi
if ! tofu output -json contracts 2>/dev/null | jq -e '.depot.release==1' >/dev/null 2>&1; then
  printf '%s\n' 'contracts.depot.release = 1: ✗'
  failed=1
fi
if ! jq -e '.configuration.root_module.module_calls.station.source=="./modules/v2"' upgrade-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'upgrade-plan.json station.source = ./modules/v2: ✗'
  failed=1
fi
if ! jq -e '.configuration.root_module.module_calls.depot.source=="./modules/v1"' upgrade-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'upgrade-plan.json depot.source = ./modules/v1: ✗'
  failed=1
fi
if ! jq -e 'all(.resource_changes[]; .change.actions==["no-op"])' upgrade-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'upgrade-plan.json resource_changes actions = ["no-op"]: ✗'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗'
  failed=1
fi
exit "$failed"
