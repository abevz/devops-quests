set -euo pipefail
cd ~/quest
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
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-43\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
git -C repository remote add origin "$GIT_URL"
git -C repository add manifests
git -C repository commit -m 'Record station desired state'
git -C repository push -u origin main
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
