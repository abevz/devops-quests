set -euo pipefail
cd ~/quest
cat > role.yaml <<'DQ_ASSET'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: station-reader
rules:
- apiGroups:
  - ''
  resources:
  - configmaps
  resourceNames:
  - route
  verbs:
  - get
DQ_ASSET
python3 - role.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f role.yaml
python3 - binding.yaml <<'DQ_YAML_FIX_125' > /tmp/restricted-binding.yaml
import sys,yaml
from pathlib import Path
value=yaml.safe_load(Path(sys.argv[1]).read_text())
value["subjects"]=[subject for subject in value["subjects"] if subject.get("name")=="controller"]
sys.stdout.write(yaml.safe_dump(value, sort_keys=False))
DQ_YAML_FIX_125
cp /tmp/restricted-binding.yaml binding.yaml
kubectl apply -f binding.yaml
