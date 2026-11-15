set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
failed=0
if ! test -s /run/dq/facts/0/safe-state.sha256 || ! test "$(sha256sum safe-state.json 2>/dev/null | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/safe-state.sha256 2>/dev/null)"; then
  printf '%s\n' 'sha256(safe-state.json) = /run/dq/facts/0/safe-state.sha256: ✗ [DQ:condition_0]'
  failed=1
fi
if ! jq -e '.resources|any(.module=="module.north" and .type=="local_file" and .name=="ledger")' safe-state.json >/dev/null 2>&1; then
  printf '%s\n' 'safe-state.json ∋ module.north.local_file.ledger: ✗ [DQ:condition_1]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(tofu state list 2>/dev/null)" = module.station.local_file.ledger; then
  printf '%s\n' 'tofu state list = module.station.local_file.ledger: ✗ [DQ:condition_2]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test -s /run/dq/facts/0/original-id || ! test "$(tofu output -raw ledger_id 2>/dev/null)" = "$(cat /run/dq/facts/0/original-id 2>/dev/null)"; then
  printf '%s\n' 'ledger_id = /run/dq/facts/0/original-id: ✗ [DQ:condition_3]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
if ! test "$(cat ledger.txt 2>/dev/null)" = north-92; then
  printf '%s\n' 'ledger.txt = north-92: ✗ [DQ:condition_4]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
failed=0
if ! jq -e '(.resource_changes|length)==1' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json resource_changes length = 1: ✗ [DQ:condition_5]'
  failed=1
fi
if ! jq -e 'all(.resource_changes[];.change.actions==["no-op"])' recovery-plan.json >/dev/null 2>&1; then
  printf '%s\n' 'recovery-plan.json resource_changes actions = ["no-op"]: ✗ [DQ:condition_6]'
  failed=1
fi
if [ "$failed" -ne 0 ]; then exit "$failed"; fi
python3 -I - <<'DQ_PROPERTY'
import json
import sys
from pathlib import Path

facts = json.loads(Path('/run/dq/facts/0/recovery-identities.json').read_text())
original = Path('/run/dq/facts/0/original-id').read_text().strip()
root = json.loads(Path('recovery-plan.json').read_text())['resource_changes']
target = json.loads(Path('infra/recovery-plan.json').read_text())['resource_changes']
expected = {'docker_container': facts['container_id'], 'docker_network': facts['network_id'], 'docker_volume': facts['volume_name'], 'terraform_data': facts['progress_id']}
valid_root = len(root) == 1 and root[0].get('mode') == 'managed' and root[0].get('type') == 'local_file' and root[0].get('address') == 'module.station.local_file.ledger'
valid_root = valid_root and root[0].get('change', {}).get('before', {}).get('id') == original and root[0].get('change', {}).get('after', {}).get('id') == original
managed = [row for row in target if row.get('mode') == 'managed']
valid_target = len(managed) == len(expected) and {r.get('type') for r in managed} == set(expected)
for row in managed:
    kind = row.get('type')
    change = row.get('change', {})
    valid_target = valid_target and kind in expected and change.get('actions') == ['no-op'] and change.get('before', {}).get('id') == expected.get(kind) and change.get('after', {}).get('id') == expected.get(kind)
    valid_target = valid_target and (kind == 'terraform_data' or row.get('address', '').startswith('module.fabric.'))
valid_target = valid_target and all(row.get('mode') == 'managed' or (row.get('mode') == 'data' and row.get('change', {}).get('actions') in (['read'], ['no-op'])) for row in target)
if not (valid_root and valid_target):
    print('Saved plans must retain each original managed binding: ✗ [DQ:recovery_plans]')
    sys.exit(1)
DQ_PROPERTY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
  printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_4]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
failed=0
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then
  printf '%s\n' 'tofu plan -input=false -detailed-exitcode -no-color → 0: ✗ [DQ:condition_7]'
  failed=1
fi
if [ "$failed" -ne 0 ]; then exit "$failed"; fi
python3 -I - <<'DQ_PROPERTY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Recovery requirement is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker, *, binary=False):
    try:
        result = subprocess.run(args, capture_output=True, text=not binary, timeout=30)
        if result.returncode:
            raise ValueError('CLI could not observe the current input')
        return result.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current recovery inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    try:
        return json.loads(command(args, marker))
    except ValueError:
        print('Current recovery document is invalid: ✗ [DQ:' + marker + ']')
        sys.exit(1)

facts = json.loads(Path('/run/dq/facts/0/recovery-identities.json').read_text())
original = Path('/run/dq/facts/0/original-id').read_text().strip()
root = document(['tofu', 'state', 'pull'], 'recovery_target')
target = document(['tofu', '-chdir=infra', 'state', 'pull'], 'recovery_target')
for prefix, state in [('root', root), ('infra', target)]:
    require(state.get('lineage') == facts[prefix + '_lineage'] and type(state.get('serial')) is int and state['serial'] >= facts[prefix + '_serial'], 'recovery_lineage')
managed = [r for r in target.get('resources', []) if r.get('mode') == 'managed']
expected = {'docker_container': facts['container_id'], 'docker_network': facts['network_id'], 'docker_volume': facts['volume_name'], 'terraform_data': facts['progress_id']}
valid = len(managed) == len(expected) and {r.get('type') for r in managed} == set(expected)
for row in managed:
    instances = row.get('instances', [])
    valid = valid and len(instances) == 1 and instances[0].get('attributes', {}).get('id') == expected.get(row.get('type'))
    if row.get('type') == 'terraform_data':
        attrs = instances[0].get('attributes', {}) if instances else {}
        valid = valid and attrs.get('input') == facts['progress_input'] and attrs.get('output') == facts['progress_output']
    else:
        module = row.get('module', '')
        valid = valid and isinstance(module, str) and (module == 'module.fabric' or module.startswith('module.fabric.'))
require(valid, 'recovery_target')
ledger = [i for r in root.get('resources', []) if r.get('mode') == 'managed' and r.get('type') == 'local_file' and r.get('module') == 'module.station' and r.get('name') == 'ledger' for i in r.get('instances', [])]
require(len(ledger) == 1 and ledger[0].get('attributes', {}).get('id') == original, 'recovery_identity')
worker = document(['docker', 'inspect', facts['container_id']], 'recovery_identity')[0]
volume = document(['docker', 'volume', 'inspect', facts['volume_name']], 'recovery_identity')[0]
networks = worker.get('NetworkSettings', {}).get('Networks', {})
mounts = worker.get('Mounts', [])
require(worker.get('Id') == facts['container_id'] and worker.get('State', {}).get('Running') is True and any(n.get('NetworkID') == facts['network_id'] for n in networks.values()) and any(m.get('Type') == 'volume' and m.get('Name') == facts['volume_name'] and m.get('Destination') == '/data' for m in mounts) and volume.get('CreatedAt') == facts['volume_created_at'], 'recovery_identity')
data = command(['docker', 'exec', facts['container_id'], 'cat', '/data/ledger'], 'recovery_data', binary=True)
require(hashlib.sha256(data).hexdigest() == facts['data_sha256'], 'recovery_data')
output = document(['tofu', '-chdir=infra', 'output', '-json', 'runtime'], 'recovery_target')
require(output == {'container_id': facts['container_id'], 'network_id': facts['network_id'], 'volume_name': facts['volume_name']}, 'recovery_target')
for prefix, filename in [('root', 'before-recovery.tfstate'), ('infra', 'infra/before-recovery.tfstate')]:
    try:
        value = json.loads(Path(filename).read_text())
        digest = hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        require(digest == facts[prefix + '_backup_sha256'], 'recovery_backups')
    except (ValueError, OSError):
        require(False, 'recovery_backups')
result = subprocess.run(['tofu', '-chdir=infra', 'plan', '-input=false', '-detailed-exitcode', '-no-color'], capture_output=True, timeout=60)
require(result.returncode == 0, 'recovery_convergence')
sys.exit(int(failed))
DQ_PROPERTY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
  printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_5]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
