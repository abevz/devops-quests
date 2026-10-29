set -euo pipefail
cd ~/quest
failed=0
if ! test "$(cat east.txt 2>/dev/null)" = open; then
  printf '%s\n' 'east.txt = open: ✗'
  failed=1
fi
if ! tofu output -json routes > current-ids.json 2>/dev/null; then
  printf '%s\n' 'tofu output -json routes: ✗'
  failed=1
fi
if ! jq -e --slurpfile old original-ids.json '.north==$old[0].north' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes.north = original-ids.json north: ✗'
  failed=1
fi
if ! jq -e --slurpfile old original-ids.json '.south==$old[0].south' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes.south = original-ids.json south: ✗'
  failed=1
fi
if ! jq -e '(.east|type)=="string"' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes.east type = string: ✗'
  failed=1
fi
if ! jq -e 'length==3' current-ids.json >/dev/null 2>&1; then
  printf '%s\n' 'routes length = 3: ✗'
  failed=1
fi
if ! tofu state list 2>/dev/null | grep -Fx 'local_file.route["east"]' >/dev/null; then
  printf '%s\n' 'tofu state list ∋ local_file.route["east"]: ✗'
  failed=1
fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗'
  failed=1
fi
if ! test "$(cat north.txt 2>/dev/null)" = open; then
  printf '%s\n' 'north.txt = open: ✗'
  failed=1
fi
if ! test "$(cat south.txt 2>/dev/null)" = held; then
  printf '%s\n' 'south.txt = held: ✗'
  failed=1
fi
exit "$failed"
