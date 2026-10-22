set -euo pipefail
cd ~/quest
cat > role.json <<'DQ_ASSET'
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "Role",
  "metadata": {
    "name": "station-reader"
  },
  "rules": [
    {
      "apiGroups": [
        ""
      ],
      "resources": [
        "configmaps"
      ],
      "resourceNames": [
        "route"
      ],
      "verbs": [
        "get"
      ]
    }
  ]
}
DQ_ASSET
python3 - role.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f role.json
jq '.subjects=[.subjects[]|select(.name=="controller")]' binding.json > /tmp/restricted-binding.json
cp /tmp/restricted-binding.json binding.json
kubectl apply -f binding.json
