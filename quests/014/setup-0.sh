set -euo pipefail
cd ~/quest
cat > route.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "route"
  },
  "data": {
    "name": "south"
  }
}
DQ_ASSET
python3 - route.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.json
cat > worker.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "route-worker"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "route-worker"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "route-worker"
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
              "if [ \"$ROUTE\" != north ]; then echo \"route must equal north\" >&2; exit 3; fi; exec sleep 3600"
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
            "env": [
              {
                "name": "ROUTE",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "route",
                    "key": "name"
                  }
                }
              }
            ]
          }
        ]
      }
    }
  }
}
DQ_ASSET
python3 - worker.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f worker.json
