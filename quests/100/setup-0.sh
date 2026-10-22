set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
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
            "image": "__PRIVATE_IMAGE__",
            "imagePullPolicy": "Always",
            "command": [
              "sh",
              "-c",
              "test \"$ROUTE_SECRET\" = north-secret; mkdir -p /tmp/site; printf \"%s\\n\" \"north-100\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
                "name": "ROUTE_SECRET",
                "valueFrom": {
                  "secretKeyRef": {
                    "name": "route-secret",
                    "key": "value"
                  }
                }
              }
            ]
          }
        ],
        "imagePullSecrets": [
          {
            "name": "registry-pull"
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
cat > repository/manifests/service.json <<'DQ_ASSET'
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
python3 - repository/manifests/service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'IMAGE'
from pathlib import Path
import os
p=Path('repository/manifests/board.json');p.write_text(p.read_text().replace('__PRIVATE_IMAGE__',os.environ['PRIVATE_IMAGE']))
IMAGE
git -C repository add .
git -C repository commit -m 'Publish secret-backed private board'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
jq -n --arg image "$PRIVATE_IMAGE" '{image:$image}' > private-release.json
cat > application.json <<'DQ_ASSET'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Application",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "project": "station",
    "source": {
      "repoURL": "__GIT_URL__",
      "path": "manifests",
      "targetRevision": "main"
    },
    "destination": {
      "server": "https://kubernetes.default.svc",
      "namespace": "__NAMESPACE__"
    },
    "syncPolicy": {
      "automated": {
        "prune": true,
        "selfHeal": true
      }
    }
  }
}
DQ_ASSET
python3 - <<'APP'
import os
from pathlib import Path
p=Path('application.json');p.write_text(p.read_text().replace('__GIT_URL__',os.environ['GIT_URL']).replace('__NAMESPACE__',os.environ['DQ_NAMESPACE']))
APP
kubectl apply -f application.json
kubectl patch application board --type=merge -p '{"spec":{"source":{"path":"retired"}}}'
cp release-commit baseline-commit
# The initial private image and Vault credentials are deliberately absent from Kubernetes.
