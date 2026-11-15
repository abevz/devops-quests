set -euo pipefail
cd ~/quest
helm upgrade board ./chart --reset-values -f chart/values.yaml --wait --timeout=90s
for release in dispatcher archive; do
 helm upgrade "$release" "./$release" --reset-values -f "$release/values.yaml" --wait --timeout=90s
done
python3 -I - <<'DQ_PUBLICATION'
import json,subprocess,time
from pathlib import Path
contract=json.loads(Path('release-contract.json').read_text())
producer=contract['producer']
cm=json.loads(subprocess.run(['kubectl','get','configmap',producer['configMap'],'-o','json'],capture_output=True,text=True,check=True).stdout)
expected=json.loads(cm['data']['release.json'])
for endpoint in [producer]+contract['consumers']:
    deadline=time.monotonic()+30
    consecutive=0
    while time.monotonic()<deadline:
        result=subprocess.run(['kubectl','exec','deployment/'+producer['deployment'],'-c','worker','--','wget','-qO-','-T','3','http://'+endpoint['service']+':'+str(contract['servicePort'])+contract['metadataPath']],capture_output=True,text=True,timeout=10)
        try:
            correct=result.returncode==0 and json.loads(result.stdout)==expected
        except ValueError:correct=False
        consecutive=consecutive+1 if correct else 0
        if consecutive>=2:break
        time.sleep(.3)
    assert consecutive>=2,endpoint['service']
DQ_PUBLICATION
kubectl rollout status deployment/relay --timeout=90s
test "$(kubectl exec deployment/relay -- wget -qO- -T 3 http://127.0.0.1:8080)" = signalrail
