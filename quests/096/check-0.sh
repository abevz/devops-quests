set -euo pipefail
cd ~/quest
test "$(sha256sum recovery.tar | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/artifact.sha256)"
python3 - <<'VERIFY'
from pathlib import Path
import yaml
p=yaml.safe_load(Path('rollout.yml').read_text())[0]
assert p['vars']['expected_sha256']==Path('/run/dq/facts/0/artifact.sha256').read_text().strip()
t=p['tasks'];assert t[0]['ansible.builtin.stat']['checksum_algorithm']=='sha256'
assert t[1]['ansible.builtin.assert']['that']==['artifact.stat.checksum == expected_sha256']
assert t[2]['ansible.builtin.unarchive']=={'src':'recovery.tar','dest':'/srv/site','owner':'root','group':'root','mode':'0644'}
assert t[2]['notify']=='Reload station' and p['serial']==1
VERIFY
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-96; test "$(stat -c %a /srv/site/message)" = 644; test "$(stat -c %u:%g /srv/site/message)" = 0:0'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-96; test "$(stat -c %a /srv/site/message)" = 644; test "$(stat -c %u:%g /srv/site/message)" = 0:0'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/message)" = north-96; test "$(stat -c %a /srv/site/message)" = 644; test "$(stat -c %u:%g /srv/site/message)" = 0:0'
for n in 1 2 3; do test "$(curl -fsS "http://app$n-${DQ_NAMESPACE#dq-}:8080")" = north-96; done
