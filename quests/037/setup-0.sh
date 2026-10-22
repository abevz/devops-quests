set -euo pipefail
cd ~/quest
cat > account.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "name": "reader"
  }
}
DQ_ASSET
python3 - account.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f account.json
cat > route.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "route"
  },
  "data": {
    "route": "north"
  }
}
DQ_ASSET
python3 - route.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.json
cat > restricted.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "restricted"
  },
  "data": {
    "route": "private"
  }
}
DQ_ASSET
python3 - restricted.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f restricted.json
cat > role.json <<'DQ_ASSET'
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "Role",
  "metadata": {
    "name": "route-reader"
  },
  "rules": [
    {
      "apiGroups": [
        ""
      ],
      "resources": [
        "configmaps"
      ],
      "resourceNames": [
        "retired"
      ],
      "verbs": [
        "get"
      ]
    }
  ]
}
DQ_ASSET
python3 - role.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f role.json
cat > binding.json <<'DQ_ASSET'
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "RoleBinding",
  "metadata": {
    "name": "route-reader"
  },
  "roleRef": {
    "apiGroup": "rbac.authorization.k8s.io",
    "kind": "Role",
    "name": "route-reader"
  },
  "subjects": [
    {
      "kind": "ServiceAccount",
      "name": "reader"
    }
  ]
}
DQ_ASSET
python3 - binding.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f binding.json
cat > identity.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "identity"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "identity"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "identity"
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
        "serviceAccountName": "reader"
      }
    }
  }
}
DQ_ASSET
python3 - identity.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f identity.json
kubectl rollout status deployment/identity --timeout=60s
