set -euo pipefail
cd ~/quest
mkdir -p base
cat > base/board.json <<'DQ_ASSET'
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
              "mkdir -p /tmp/site; printf \"%s\\n\" \"$ROUTE\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
                    "key": "ROUTE"
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
python3 - base/board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p base
cat > base/service.json <<'DQ_ASSET'
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
python3 - base/service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p base
cat > base/kustomization.yaml <<'DQ_ASSET'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- board.json
- service.json
configMapGenerator:
- name: route
  literals:
  - ROUTE=retired-108
DQ_ASSET
mkdir -p overlays/recovery
cat > overlays/recovery/kustomization.yaml <<'DQ_ASSET'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
configMapGenerator:
- name: route
  behavior: replace
  literals:
  - ROUTE=north-108
patches:
- target:
    kind: Deployment
    name: retired
  patch: "- op: replace\n  path: /spec/replicas\n  value: 2\n"
DQ_ASSET
kubectl apply -k base
kubectl rollout status deployment/board --timeout=60s
kubectl get deployment board -o jsonpath='{.metadata.uid}' > original-deployment-uid
