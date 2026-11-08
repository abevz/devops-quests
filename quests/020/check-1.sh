set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = release-20; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = release-20: ✗ [DQ:content_$n]"; failed=1; fi
  if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1; fi

done
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = release-20; then
    printf '%s\n' "$host:8080 = release-20: ✗ [DQ:http_$n]"; failed=1
  fi
done
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
set -euo pipefail
cd ~/quest
replay_failed=0
if ! ANSIBLE_NOCOLOR=1 ansible-playbook rollout.yml > second-run.txt 2>&1; then printf '%s\n' 'Second delivery failed: ✗ [DQ:rerun]'; replay_failed=1; fi
python3 -I - <<'DQ_RECAP'
import json
import re
from pathlib import Path


def count(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, str) and re.fullmatch(r'[0-9]+', value):
        return int(value)
    return None


def unique_counter_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise RuntimeError('Ambiguous recap field')
        result[key] = value
    return result


def recap(text):
    # Read an actual recap, not task output which happens to mention a counter.
    records = []
    try:
        records.append(json.loads(text, object_pairs_hook=unique_counter_fields))
    except ValueError:
        for line in text.splitlines():
            try:
                records.append(json.loads(line, object_pairs_hook=unique_counter_fields))
            except ValueError:
                pass
    for record in reversed(records):
        if not isinstance(record, dict):
            continue
        stats = record.get('stats')
        if record.get('event') == 'playbook_on_stats':
            event = record.get('event_data', {})
            if isinstance(event, dict):
                stats = {host: {key: values.get(host) for key, values in event.items()
                                if isinstance(values, dict)}
                         for host in event.get('processed', {})}
        if isinstance(stats, dict):
            rows = {}
            for host, values in stats.items():
                if not isinstance(values, dict):
                    continue
                row = {}
                for key, value in values.items():
                    key = {'failures':'failed','dark':'unreachable'}.get(key, key)
                    if key in row:
                        raise RuntimeError('Ambiguous normalized recap field')
                    row[key] = count(value)
                rows[host] = row
            return rows
    rows = {}
    body = text.rsplit('PLAY RECAP', 1)[-1]
    for line in body.splitlines():
        match = re.match(r'^([^\s:]+)\s*:\s*(.*)$', line)
        if not match:
            continue
        fields = re.findall(r'\b(ok|changed|unreachable|failed|skipped|rescued|ignored)\s*=\s*([0-9]+)(?=\s|$)', match[2])
        if fields:
            # Duplicate rows cannot stand in for another managed host.
            if match[1] in rows or len({key for key, _ in fields}) != len(fields):
                return {}
            rows[match[1]] = {key: int(value) for key, value in fields}
    return rows


def require_recaps(path, required, positive=(), prefix='recap'):
    try: text = Path(path).read_text()
    except OSError: text = ''
    rows = recap(text)
    failed = False
    for number in (1, 2, 3):
        row = rows.get('app' + str(number), {})
        for key, expected in required.items():
            if key == 'unreachable' and not row:
                continue
            if row.get(key) != expected:
                marker = prefix + '_' + str(number) + '_' + key if key in ('changed', 'failed') else 'rerun'
                print('app' + str(number) + ' second delivery counter ' + key + ' must equal ' + str(expected) + ': ✗ [DQ:' + marker + ']')
                failed = True
    assert not failed, 'Every required managed host needs its own successful recap'

try:
    require_recaps('second-run.txt', {'changed':0, 'failed':0, 'unreachable':0})
except AssertionError:
    raise SystemExit(1)
except Exception:
    print('Unreadable or ambiguous delivery recap: ✗ [DQ:rerun]')
    raise SystemExit(1)
DQ_RECAP
test "$replay_failed" -eq 0
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_1_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
