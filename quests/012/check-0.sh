set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert d=={"family":"Debian","architecture":"x86_64"}'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'from pathlib import Path; p=Path("/srv/site/facts.json"); assert p.stat().st_mode & 0o777==0o644'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert d=={"family":"Debian","architecture":"x86_64"}'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'from pathlib import Path; p=Path("/srv/site/facts.json"); assert p.stat().st_mode & 0o777==0o644'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert d=={"family":"Debian","architecture":"x86_64"}'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'from pathlib import Path; p=Path("/srv/site/facts.json"); assert p.stat().st_mode & 0o777==0o644'"'"''
)
[ $? -eq 0 ] || failed=1
exit "$failed"
