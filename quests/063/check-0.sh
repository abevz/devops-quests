set -euo pipefail
cd ~/quest
failed=0
if ! sha256sum -c previous.sha256 >/dev/null 2>&1; then printf '%s\n' 'previous.txt matches previous.sha256: ✗'; failed=1; fi
if ! python3 - <<'SCOPE'
import sys
import yaml
try:
    play = yaml.safe_load(open('rollout.yml'))[0]
    task = play['tasks'][0]
    rescue = task.get('rescue') or []
    first = rescue[0] if rescue else {}
    if not all(isinstance(value, dict) for value in (play, task, first)):
        raise TypeError('play, task and rescue action must be mappings')
except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError, yaml.YAMLError):
    play, task, first = {}, {}, {}
checks = [
    ('first play hosts = fleet', play.get('hosts') == 'fleet'),
    ('first play serial = 1', type(play.get('serial')) is int and play.get('serial') == 1),
    ('first task block is a nonempty list', isinstance(task.get('block'), list) and bool(task.get('block'))),
    ('first task rescue is a nonempty list', isinstance(task.get('rescue'), list) and bool(task.get('rescue'))),
    ('first task always is a nonempty list', isinstance(task.get('always'), list) and bool(task.get('always'))),
    ('first rescue copy = previous.txt to /srv/site/message mode 0644', first.get('ansible.builtin.copy') == {'src': 'previous.txt', 'dest': '/srv/site/message', 'mode': '0644'}),
    ('first rescue notify = Reload banner', first.get('notify') == 'Reload banner'),
]
for label, ok in checks:
    if not ok: print(label + ': ✗')
sys.exit(not all(ok for _, ok in checks))
SCOPE
then failed=1; fi
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = stable-63; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi; marker=$(cat /srv/site/recovery-checked 2>/dev/null || true); if test "$marker" = checked; then printf "marker-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = stable-63: ✗"; failed=1; fi
  if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗"; failed=1; fi
  if ! grep -Fxq marker-ok <<<"$result"; then printf '%s\n' "$host /srv/site/recovery-checked = checked: ✗"; failed=1; fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = stable-63; then printf '%s\n' "$host:8080 = stable-63: ✗"; failed=1; fi
done
exit "$failed"
