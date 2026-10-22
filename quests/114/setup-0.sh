set -euo pipefail
cd ~/quest
cat > reader-sa.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "name": "reader"
  },
  "automountServiceAccountToken": false
}
DQ_ASSET
python3 - reader-sa.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f reader-sa.json
cat > role.json <<'DQ_ASSET'
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "Role",
  "metadata": {
    "name": "reader"
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
        "route"
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
    "name": "reader"
  },
  "roleRef": {
    "apiGroup": "rbac.authorization.k8s.io",
    "kind": "Role",
    "name": "reader"
  },
  "subjects": [
    {
      "kind": "ServiceAccount",
      "name": "reader",
      "namespace": "__NAMESPACE__"
    }
  ]
}
DQ_ASSET
python3 - binding.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
sed -i "s/__NAMESPACE__/$DQ_NAMESPACE/g" binding.json
kubectl apply -f binding.json
cat > route.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "route"
  },
  "data": {
    "route": "north-114"
  }
}
DQ_ASSET
python3 - route.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.json
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
                "name": "credential",
                "mountPath": "/credential",
                "readOnly": true
              }
            ]
          }
        ],
        "serviceAccountName": "reader",
        "automountServiceAccountToken": false,
        "terminationGracePeriodSeconds": 1,
        "volumes": [
          {
            "name": "credential",
            "projected": {
              "sources": [
                {
                  "serviceAccountToken": {
                    "path": "token",
                    "expirationSeconds": 600,
                    "audience": "retired.station"
                  }
                }
              ]
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
kubectl config view --minify --raw -o json | jq -r '.clusters[0].cluster["certificate-authority-data"]' | base64 -d > api-ca.pem
kubectl config view --minify -o json | jq -r '.clusters[0].cluster.server' > api-endpoint
kubectl create configmap offlimits --from-literal=route=closed
