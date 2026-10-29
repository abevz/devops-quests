set -euo pipefail
cd ~/quest
source platform.env
jq -n --arg image "$PRIVATE_IMAGE" '{image:$image}' > private-release.json
python3 - <<'DQ_REGISTRY_SECRET'
import base64
import json
import os
import tempfile

registry = os.environ['REGISTRY']
username = os.environ['REGISTRY_USER']
password = os.environ['REGISTRY_PASSWORD']
auth = base64.b64encode((username + ':' + password).encode()).decode()
config = {'auths': {registry: {'username': username, 'password': password, 'auth': auth}}}
secret = {
    'apiVersion': 'v1',
    'kind': 'Secret',
    'metadata': {'name': 'registry-pull'},
    'type': 'kubernetes.io/dockerconfigjson',
    'data': {'.dockerconfigjson': base64.b64encode(json.dumps(config).encode()).decode()},
}
fd, temporary = tempfile.mkstemp(prefix='.registry-pull-', dir='.')
try:
    with os.fdopen(fd, 'w') as stream:
        json.dump(secret, stream)
    os.replace(temporary, 'registry-pull.json')
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
DQ_REGISTRY_SECRET
kubectl apply -f registry-pull.json >/dev/null
source platform.env
mkdir -p repository/manifests
cat > repository/manifests/board.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "board"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "board"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "runAsGroup": 1000,
          "fsGroup": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "__PRIVATE_TAG__",
            "imagePullPolicy": "Always",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-80\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "8Mi"
              },
              "limits": {
                "cpu": "200m",
                "memory": "32Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            }
          }
        ],
        "imagePullSecrets": [
          {
            "name": "registry-pull"
          }
        ]
      }
    }
  }
}
DQ_ASSET
python3 - repository/manifests/board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'TAG'
import os
from pathlib import Path
p=Path('repository/manifests/board.json');p.write_text(p.read_text().replace('__PRIVATE_TAG__',os.environ['REGISTRY']+'/parcel:retired'))
TAG
mkdir -p repository/manifests
cat > repository/manifests/service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "selector": {
      "app": "board"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": 8080
      }
    ]
  }
}
DQ_ASSET
python3 - repository/manifests/service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
cd repository
git remote add origin "$GIT_URL"
git add .
git commit -m 'Publish station board'
git push -u origin main
git rev-parse HEAD > ../release-commit
cd ..
cat > application.json <<'DQ_ASSET'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Application",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "project": "station",
    "source": {
      "repoURL": "__GIT_URL__",
      "path": "retired",
      "targetRevision": "main"
    },
    "destination": {
      "server": "https://kubernetes.default.svc",
      "namespace": "__NAMESPACE__"
    },
    "syncPolicy": {
      "automated": {
        "prune": true,
        "selfHeal": true
      }
    }
  }
}
DQ_ASSET
python3 - <<'APP'
import os
from pathlib import Path
p=Path('application.json');p.write_text(p.read_text().replace('__GIT_URL__',os.environ['GIT_URL']).replace('__NAMESPACE__',os.environ['DQ_NAMESPACE']))
APP
kubectl apply -f application.json
cp release-commit baseline-commit
