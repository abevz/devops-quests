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








from dq_check import ansible_recap as recap


from dq_check import require_recaps as _dq_recaps

def require_recaps(path, required, positive=(), prefix="recap"):
    return _dq_recaps(path, required, positive, prefix, dialect='by_counter')

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
