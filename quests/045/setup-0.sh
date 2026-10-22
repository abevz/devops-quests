set -euo pipefail
cd ~/quest
cat > claim.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "PersistentVolumeClaim",
  "metadata": {
    "name": "route-data"
  },
  "spec": {
    "accessModes": [
      "ReadWriteOnce"
    ],
    "storageClassName": "standard",
    "resources": {
      "requests": {
        "storage": "8Mi"
      }
    }
  }
}
DQ_ASSET
python3 - claim.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f claim.json
cat > seed.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "seed"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "seed"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "seed"
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
              "printf \"%s\\n\" north-45 > /data/route.txt; exec sleep 3600"
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
                "mountPath": "/data"
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
python3 - seed.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f seed.json
kubectl rollout status deployment/seed --timeout=60s
kubectl exec deployment/seed -- test -s /data/route.txt
kubectl get pvc route-data -o jsonpath='{.metadata.uid}' > original-pvc-uid
kubectl delete deployment seed --wait=true
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
              "claimName": "retired-data"
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
