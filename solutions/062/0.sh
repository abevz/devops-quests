set -euo pipefail
cd ~/quest
cat > policy.yaml <<'DQ_ASSET'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: board-ingress
spec:
  podSelector:
    matchLabels:
      app: board
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: dispatcher
    ports:
    - protocol: TCP
      port: 8080
DQ_ASSET
python3 - policy.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f policy.yaml
sleep 3
python3 -I - <<'DQ_CALLER_REFERENCE'
import json,subprocess
policy=json.loads(subprocess.check_output(['kubectl','get','networkpolicy','board-ingress','-o','json'],text=True))
labels=policy['spec']['ingress'][0]['from'][0]['podSelector']['matchLabels']
patch={'spec':{'template':{'metadata':{'labels':labels}}}}
subprocess.run(['kubectl','patch','deployment','dispatcher','--type=merge','-p',json.dumps(patch)],check=True)
subprocess.run(['kubectl','rollout','status','deployment/dispatcher','--timeout=90s'],check=True)
DQ_CALLER_REFERENCE
for i in $(seq 1 30); do
 if test "$(kubectl exec deployment/dispatcher -- wget -qO- -T 2 http://board:8080)" = north-62; then exit 0; fi
 sleep 1
done
exit 1
