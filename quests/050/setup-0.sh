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
              "httpd",
              "-f",
              "-p",
              "8080",
              "-h",
              "/site"
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
            },
            "volumeMounts": [
              {
                "name": "notice",
                "mountPath": "/site",
                "readOnly": true
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "notice",
            "configMap": {
              "name": "route"
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
mkdir -p repository/manifests
cat > repository/manifests/route.json <<'DQ_ASSET'
{"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "route"}, "data": {"index.html": "retired"}}
DQ_ASSET
git -C repository remote add origin "$GIT_URL"
git -C repository add manifests
git -C repository commit -m 'Record station desired state'
git -C repository push -u origin main
git -C repository rev-parse HEAD > baseline-commit
git -C repository switch -c release-candidate
mkdir -p repository/manifests
cat > repository/manifests/route.json <<'DQ_ASSET'
{"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "route"}, "data": {"index.html": "north-50"}}
DQ_ASSET
git -C repository add manifests/route.json
git -C repository commit -m 'Prepare north board release'
git -C repository push -u origin release-candidate
git -C repository switch main
