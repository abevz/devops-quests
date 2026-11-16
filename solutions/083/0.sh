set -euo pipefail
cd ~/quest
cat > reader.hcl <<'DQ_ASSET'
path "secret/data/dispatch" { capabilities = ["read"] }
DQ_ASSET
source platform.env
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H "Content-Type: application/json" --request PUT --data "$(jq -n --rawfile policy reader.hcl '{policy:$policy}')" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null
cat > sync-secret.sh <<'DQ_CONSTRUCTOR'
#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
umask 077
delivery_dir=$(mktemp -d)
trap 'rm -rf "$delivery_dir"' EXIT
python3 -I - "$delivery_dir/header" <<'HEADER'
import os,sys
from pathlib import Path
Path(sys.argv[1]).write_text('X-Vault-Token: '+os.environ['VAULT_READER_TOKEN']+'\n')
HEADER
curl -fsS --max-time 3 -H @"$delivery_dir/header" "$VAULT_ADDR/v1/secret/data/dispatch" > "$delivery_dir/response.json"
python3 -I - "$delivery_dir" <<'VALUE'
import json,sys
from pathlib import Path
folder=Path(sys.argv[1])
value=json.loads((folder/'response.json').read_text())['data']['data']['value']
assert isinstance(value,str)
(folder/'value').write_text(value)
VALUE
kubectl create secret generic route-secret --from-file="value=$delivery_dir/value" --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/relay
kubectl rollout status deployment/relay --timeout=90s

DQ_CONSTRUCTOR
bash sync-secret.sh
kubectl rollout status deployment/relay --timeout=90s

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
