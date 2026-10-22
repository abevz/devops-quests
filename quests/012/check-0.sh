set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert d=={"family":"Debian","architecture":"x86_64"}; assert p.stat().st_mode & 0o777==0o644'"'"''
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert d=={"family":"Debian","architecture":"x86_64"}; assert p.stat().st_mode & 0o777==0o644'"'"''
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'python3 -c '"'"'import json; from pathlib import Path; p=Path("/srv/site/facts.json"); d=json.loads(p.read_text()); assert d=={"family":"Debian","architecture":"x86_64"}; assert p.stat().st_mode & 0o777==0o644'"'"''
