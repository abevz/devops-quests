set -euo pipefail
cd ~/quest
source platform.env
for i in 0 1; do
 jq -n --arg key "$(jq -er ".[$i]" unseal-shares.json)" '{key:$key}' > unseal-request.json
 chmod 600 unseal-request.json
 curl -fsS -H 'Content-Type: application/json' --request PUT --data-binary @unseal-request.json "$VAULT_ADDR/v1/sys/unseal" > unseal-status.json
done
rm unseal-request.json

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
printf '%s' '{"upstream":"http://127.0.0.1:18081"}' > downstream/source.json
kill -HUP "$(cat downstream/application.pid)"
for _ in $(seq 1 30); do
 if curl -fsS --max-time 1 http://127.0.0.1:18082/ >/dev/null; then break; fi
 sleep 0.2
done
curl -fsS --max-time 1 http://127.0.0.1:18082/ >/dev/null
