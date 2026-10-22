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
    "route": "north-101\n"
  }
}
DQ_ASSET
python3 - route.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.json
cat > board.json <<'DQ_ASSET'
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
              "/shared"
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
                "name": "shared",
                "mountPath": "/shared",
                "readOnly": true
              }
            ],
            "readinessProbe": {
              "httpGet": {
                "path": "/route",
                "port": 8080
              },
              "periodSeconds": 1
            }
          }
        ],
        "initContainers": [
          {
            "name": "prepare",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "cp /input/missing /shared/route"
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
                "name": "input",
                "mountPath": "/input",
                "readOnly": true
              },
              {
                "name": "shared",
                "mountPath": "/shared"
              }
            ]
          },
          {
            "name": "watcher",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "while :; do date +%s > /shared/heartbeat; sleep 1; done"
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
            "restartPolicy": "Always",
            "startupProbe": {
              "exec": {
                "command": [
                  "test",
                  "-s",
                  "/shared/heartbeat"
                ]
              },
              "periodSeconds": 1,
              "failureThreshold": 10
            },
            "volumeMounts": [
              {
                "name": "shared",
                "mountPath": "/shared"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "input",
            "configMap": {
              "name": "route"
            }
          },
          {
            "name": "shared",
            "emptyDir": {}
          }
        ]
      }
    }
  }
}
DQ_ASSET
python3 - board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.json
cat > service.json <<'DQ_ASSET'
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
python3 - service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.json
