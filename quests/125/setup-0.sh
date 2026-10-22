set -euo pipefail
cd ~/quest
cat > controller-sa.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "name": "controller"
  },
  "automountServiceAccountToken": false
}
DQ_ASSET
python3 - controller-sa.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f controller-sa.json
cat > controller.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "controller"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "controller"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "controller"
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
        "serviceAccountName": "controller",
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
                    "audience": "https://kubernetes.default.svc.cluster.local"
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
python3 - controller.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f controller.json
cat > observer-sa.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "name": "observer"
  },
  "automountServiceAccountToken": false
}
DQ_ASSET
python3 - observer-sa.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f observer-sa.json
cat > observer.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "observer"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "observer"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "observer"
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
        "serviceAccountName": "observer",
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
                    "audience": "https://kubernetes.default.svc.cluster.local"
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
python3 - observer.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f observer.json
cat > role.json <<'DQ_ASSET'
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "Role",
  "metadata": {
    "name": "station-reader"
  },
  "rules": [
    {
      "apiGroups": [
        ""
      ],
      "resources": [
        "configmaps",
        "secrets"
      ],
      "verbs": [
        "get",
        "list",
        "watch"
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
    "name": "station-reader"
  },
  "roleRef": {
    "apiGroup": "rbac.authorization.k8s.io",
    "kind": "Role",
    "name": "station-reader"
  },
  "subjects": [
    {
      "kind": "ServiceAccount",
      "name": "controller",
      "namespace": "__NAMESPACE__"
    },
    {
      "kind": "ServiceAccount",
      "name": "observer",
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
    "route": "north-125"
  }
}
DQ_ASSET
python3 - route.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.json
cat > offlimits.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "offlimits"
  },
  "data": {
    "route": "closed"
  }
}
DQ_ASSET
python3 - offlimits.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f offlimits.json
cat > secret.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "control"
  },
  "stringData": {
    "value": "synthetic-control"
  }
}
DQ_ASSET
python3 - secret.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f secret.json
kubectl rollout status deployment/controller --timeout=90s
kubectl rollout status deployment/observer --timeout=90s
kubectl config view --minify --raw -o json | jq -r '.clusters[0].cluster["certificate-authority-data"]' | base64 -d > api-ca.pem
kubectl config view --minify -o json | jq -r '.clusters[0].cluster.server' > api-endpoint
