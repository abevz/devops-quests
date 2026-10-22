set -euo pipefail
cd ~/quest
source platform.env
cat > application.json <<'DQ_ASSET'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Application",
  "metadata": {
    "name": "station"
  },
  "spec": {
    "project": "station",
    "source": {
      "repoURL": "__GIT_URL__",
      "targetRevision": "main",
      "path": "retired"
    },
    "destination": {
      "server": "https://kubernetes.default.svc",
      "namespace": "__TARGET_NS__"
    }
  }
}
DQ_ASSET
python3 - <<'APP'
import os
from pathlib import Path
p=Path('application.json');p.write_text(p.read_text().replace('__GIT_URL__',os.environ['GIT_URL']).replace('__TARGET_NS__',os.environ['DQ_NAMESPACE']))
APP
kubectl apply -f application.json
