set -euo pipefail
cd ~/quest
cat > reader.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "reader"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "reader"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "reader"
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
              "sleep",
              "3600"
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
                "name": "data",
                "mountPath": "/data",
                "readOnly": true
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "data",
            "persistentVolumeClaim": {
              "claimName": "route-data"
            }
          }
        ]
      }
    }
  }
}
DQ_ASSET
python3 - reader.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f reader.json
kubectl rollout status deployment/reader --timeout=90s
