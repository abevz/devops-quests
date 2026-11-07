set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_group_failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert isinstance(d,dict) and d.get("family")=="Debian" and d.get("architecture")=="x86_64"'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'The JSON record /srv/site/facts.json on app1 identifies family Debian and architecture x86_64 : ✗ [DQ:facts_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert isinstance(d,dict) and d.get("family")=="Debian" and d.get("architecture")=="x86_64"'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'The JSON record /srv/site/facts.json on app2 identifies family Debian and architecture x86_64 : ✗ [DQ:facts_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert isinstance(d,dict) and d.get("family")=="Debian" and d.get("architecture")=="x86_64"'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'The JSON record /srv/site/facts.json on app3 identifies family Debian and architecture x86_64 : ✗ [DQ:facts_3]'
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
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'from pathlib import Path; p=Path("/srv/site/facts.json"); assert p.stat().st_mode & 0o777==0o644'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app1, /srv/site/facts.json has mode 0644 : ✗ [DQ:mode_1]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'from pathlib import Path; p=Path("/srv/site/facts.json"); assert p.stat().st_mode & 0o777==0o644'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app2, /srv/site/facts.json has mode 0644 : ✗ [DQ:mode_2]'
dq_group_failed=1
fi
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'from pathlib import Path; p=Path("/srv/site/facts.json"); assert p.stat().st_mode & 0o777==0o644'"'"''
)
dq_condition_rc=$?
if [ "$dq_condition_rc" -ne 0 ]; then
printf '%s\n' 'On app3, /srv/site/facts.json has mode 0644 : ✗ [DQ:mode_3]'
dq_group_failed=1
fi
set -e
test "$dq_group_failed" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
