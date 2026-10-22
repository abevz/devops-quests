set -euo pipefail
cd ~/quest
cat > shelf.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "StatefulSet",
  "metadata": {
    "name": "shelf"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "shelf"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "shelf"
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
              "test -s /data/index.html || echo ledger-120 > /data/index.html; exec httpd -f -p 8080 -h /data"
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
                "name": "ledger",
                "mountPath": "/data"
              }
            ]
          }
        ],
        "terminationGracePeriodSeconds": 1
      }
    },
    "serviceName": "shelf",
    "volumeClaimTemplates": [
      {
        "metadata": {
          "name": "ledger"
        },
        "spec": {
          "accessModes": [
            "ReadWriteOnce"
          ],
          "resources": {
            "requests": {
              "storage": "16Mi"
            }
          }
        }
      }
    ]
  }
}
DQ_ASSET
python3 - shelf.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f shelf.json
cat > service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "shelf"
  },
  "spec": {
    "selector": {
      "app": "retired"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": 8080
      }
    ],
    "clusterIP": "None"
  }
}
DQ_ASSET
python3 - service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.json
cat > client.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "client"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "client"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "client"
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
            }
          }
        ],
        "terminationGracePeriodSeconds": 1
      }
    }
  }
}
DQ_ASSET
python3 - client.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f client.json
kubectl rollout status statefulset/shelf --timeout=90s
kubectl get pvc ledger-shelf-0 -o jsonpath='{.metadata.uid}' > original-pvc-uid
kubectl rollout status deployment/client --timeout=90s
cat > egress.json <<'DQ_ASSET'
{
  "apiVersion": "networking.k8s.io/v1",
  "kind": "NetworkPolicy",
  "metadata": {
    "name": "client-egress"
  },
  "spec": {
    "podSelector": {
      "matchLabels": {
        "app": "client"
      }
    },
    "policyTypes": [
      "Egress"
    ],
    "egress": []
  }
}
DQ_ASSET
python3 - egress.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f egress.json
