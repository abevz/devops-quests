set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_ATTACHMENT_REFERENCE'
import json,subprocess
gateway=json.loads(subprocess.check_output(['kubectl','get','gateway','station','-o','json'],text=True))
listener=next(item for item in gateway['spec']['listeners'] if item.get('protocol')=='HTTP')
patch=[{'op':'replace','path':'/spec/parentRefs/0/sectionName','value':listener['name']}]
subprocess.run(['kubectl','patch','httproute','board','--type=json','-p',json.dumps(patch)],check=True)
DQ_ATTACHMENT_REFERENCE
set -euo pipefail
cd ~/quest
kubectl patch httproute board --type=json -p '[{"op": "replace", "path": "/spec/rules/0/backendRefs/0/port", "value": 8080}]'
url=$(jq -r .url /run/dq/facts/0/gateway-target.json)
for i in $(seq 1 30); do
 if test "$(kubectl exec deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url")" = north-113; then break; fi
 sleep 1
done
