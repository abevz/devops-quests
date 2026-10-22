set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
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
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-122\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
        "terminationGracePeriodSeconds": 1
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
mkdir -p repository/apps
cat > repository/apps/child.json <<'DQ_ASSET'
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
python3 - repository/apps/child.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
cat > parent.json <<'DQ_ASSET'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Application",
  "metadata": {
    "name": "parent"
  },
  "spec": {
    "project": "station",
    "source": {
      "repoURL": "__GIT_URL__",
      "path": "apps",
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
python3 - parent.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'TARGETS'
import os
from pathlib import Path
for p in Path('.').glob('**/*.json'):
 if '.git' in p.parts: continue
 p.write_text(p.read_text().replace('__GIT_URL__',os.environ['GIT_URL']).replace('__NAMESPACE__',os.environ['DQ_NAMESPACE']))
TARGETS
git -C repository add .
git -C repository commit -m 'Describe child application and board'
git -C repository push origin main
git -C repository rev-parse HEAD > baseline-commit
kubectl apply -f parent.json
cat > wait-apps.sh <<'DQ_ASSET'
#!/usr/bin/env bash
set -euo pipefail
revision=$(git -C repository rev-parse HEAD)
kubectl get application parent board -o json | jq -e --arg rev "$revision" '(.items|length)==2 and all(.items[]; .status.sync.status=="Synced" and .status.sync.revision==$rev)' >/dev/null
kubectl get application board -o json | jq -e '.status.health.status=="Healthy"' >/dev/null
DQ_ASSET
kubectl get application parent -o jsonpath='{.metadata.uid}' > parent-uid
