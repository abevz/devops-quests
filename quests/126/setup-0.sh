set -euo pipefail
cd ~/quest
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
kubectl rollout status deployment/client --timeout=90s
cat > quota.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ResourceQuota",
  "metadata": {
    "name": "station"
  },
  "spec": {
    "hard": {
      "requests.cpu": "200m",
      "limits.cpu": "400m",
      "requests.memory": "32Mi",
      "limits.memory": "64Mi",
      "pods": "2"
    }
  }
}
DQ_ASSET
python3 - quota.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f quota.json
cat > defaults.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "LimitRange",
  "metadata": {
    "name": "defaults"
  },
  "spec": {
    "limits": [
      {
        "type": "Container",
        "default": {
          "cpu": "400m",
          "memory": "32Mi"
        },
        "defaultRequest": {
          "cpu": "300m",
          "memory": "16Mi"
        }
      }
    ]
  }
}
DQ_ASSET
python3 - defaults.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f defaults.json
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
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-126\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
            ],
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
