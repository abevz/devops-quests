set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
if ! test -s repair.log; then printf '%s\n' 'repair.log empty: ✗ [DQ:repair]'; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_result_failed=0
set +e
(
set -e
python3 -I - <<'DQ_RECAP'
import json
import re
from pathlib import Path








from dq_check import ansible_recap as recap


from dq_check import require_recaps as _dq_recaps

def require_recaps(path, required, positive=(), prefix="recap"):
    return _dq_recaps(path, required, positive, prefix, dialect='by_host')

require_recaps('second.log', {'changed':0,'unreachable':0,'failed':0})
DQ_RECAP
)
[ $? -eq 0 ] || dq_result_failed=1
set -e
test "$dq_result_failed" -eq 0
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/config 2>/dev/null)" = 755; then printf '"'"'%s\n'"'"' '"'"'app1 /srv/site/config: ✗ [DQ:host_1_dir_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app1 SSH: ✗ [DQ:ssh_1]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/config 2>/dev/null)" = 755; then printf '"'"'%s\n'"'"' '"'"'app2 /srv/site/config: ✗ [DQ:host_2_dir_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app2 SSH: ✗ [DQ:ssh_2]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/config 2>/dev/null)" = 755; then printf '"'"'%s\n'"'"' '"'"'app3 /srv/site/config: ✗ [DQ:host_3_dir_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app3 SSH: ✗ [DQ:ssh_3]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf '"'"'%s\n'"'"' '"'"'app1 /srv/site/message: ✗ [DQ:host_1_banner_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app1 SSH: ✗ [DQ:ssh_1]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/config/route 2>/dev/null)" = 644; then printf '"'"'%s\n'"'"' '"'"'app1 /srv/site/config/route: ✗ [DQ:host_1_route_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app1 SSH: ✗ [DQ:ssh_1]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf '"'"'%s\n'"'"' '"'"'app2 /srv/site/message: ✗ [DQ:host_2_banner_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app2 SSH: ✗ [DQ:ssh_2]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/config/route 2>/dev/null)" = 644; then printf '"'"'%s\n'"'"' '"'"'app2 /srv/site/config/route: ✗ [DQ:host_2_route_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app2 SSH: ✗ [DQ:ssh_2]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf '"'"'%s\n'"'"' '"'"'app3 /srv/site/message: ✗ [DQ:host_3_banner_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app3 SSH: ✗ [DQ:ssh_3]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'if ! test "$(stat -c %a /srv/site/config/route 2>/dev/null)" = 644; then printf '"'"'%s\n'"'"' '"'"'app3 /srv/site/config/route: ✗ [DQ:host_3_route_mode]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app3 SSH: ✗ [DQ:ssh_3]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'if ! test "$(cat /srv/site/message 2>/dev/null)" = north-79; then printf '"'"'%s\n'"'"' '"'"'app1 /srv/site/message: ✗ [DQ:host_1_banner_content]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app1 SSH: ✗ [DQ:ssh_1]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'if ! test "$(cat /srv/site/message 2>/dev/null)" = north-79; then printf '"'"'%s\n'"'"' '"'"'app2 /srv/site/message: ✗ [DQ:host_2_banner_content]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app2 SSH: ✗ [DQ:ssh_2]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'if ! test "$(cat /srv/site/message 2>/dev/null)" = north-79; then printf '"'"'%s\n'"'"' '"'"'app3 /srv/site/message: ✗ [DQ:host_3_banner_content]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app3 SSH: ✗ [DQ:ssh_3]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'if ! test "$(cat /srv/site/config/route 2>/dev/null)" = route=north; then printf '"'"'%s\n'"'"' '"'"'app1 /srv/site/config/route: ✗ [DQ:host_1_route_content]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app1 SSH: ✗ [DQ:ssh_1]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'if ! test "$(cat /srv/site/config/route 2>/dev/null)" = route=north; then printf '"'"'%s\n'"'"' '"'"'app2 /srv/site/config/route: ✗ [DQ:host_2_route_content]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app2 SSH: ✗ [DQ:ssh_2]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
(
set -e
dq_remote_output=$(mktemp)
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'if ! test "$(cat /srv/site/config/route 2>/dev/null)" = route=north; then printf '"'"'%s\n'"'"' '"'"'app3 /srv/site/config/route: ✗ [DQ:host_3_route_content]'"'"'; exit 1; fi' > "$dq_remote_output" 2>/dev/null; then
if ! test -s "$dq_remote_output"; then printf '%s\n' 'app3 SSH: ✗ [DQ:ssh_3]'; fi
cat "$dq_remote_output"
rm -f "$dq_remote_output"
exit 1
fi
rm -f "$dq_remote_output"
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_group_failed=0
set +e
(
set -e
test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = north-79
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app1 HTTP / on port 8080 = north-79 : ✗ [DQ:http_1]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = north-79
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app2 HTTP / on port 8080 = north-79 : ✗ [DQ:http_2]'
dq_group_failed=1
fi
(
set -e
test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = north-79
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'Host app3 HTTP / on port 8080 = north-79 : ✗ [DQ:http_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
