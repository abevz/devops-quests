set -euo pipefail
cd ~/quest
jq '.[0]' /run/dq/facts/0/audit-events.json > incident.json
cat > reader.hcl <<'DQ_ASSET'
path "secret/data/dispatch" { capabilities = ["read"] }
DQ_ASSET
source platform.env
jq -n --rawfile policy reader.hcl '{policy:$policy}' > reader-policy.json
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --request PUT --data-binary @reader-policy.json "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null

python3 -I - <<'DQ_ADOPT'
import json,os
from pathlib import Path
p=Path('consumer/source.json')
config=json.loads(p.read_text())
config['url']=os.environ['VAULT_ADDR']
config['path']='secret/data/dispatch'
p.write_text(json.dumps(config))
Path(config['token_file']).write_text(os.environ['VAULT_READER_TOKEN'])
Path(config['token_file']).chmod(0o600)
DQ_ADOPT
kill -HUP "$(cat consumer/application.pid)"
for _ in $(seq 1 30); do
 if curl -fsS --max-time 1 http://127.0.0.1:18081/ >/dev/null; then break; fi
 sleep 0.2
done
curl -fsS --max-time 1 http://127.0.0.1:18081/ >/dev/null
python3 -I - <<'DQ_INCIDENT'
import json
from pathlib import Path
events={e['path']:e for e in json.loads(Path('consumer-audit.json').read_text())}
Path('consumer-incident.json').write_text(json.dumps({'baseline':events['secret/data/dispatch'],'application':events['secret/dispatch']}))
DQ_INCIDENT
