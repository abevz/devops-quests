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
