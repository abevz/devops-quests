set -euo pipefail
cd ~/quest
source platform.env
mkdir -p variant-context
python3 - <<'VARIANT'
import os
from pathlib import Path
Path('variant-context/Dockerfile').write_text('FROM '+os.environ['PRIVATE_IMAGE']+'\nLABEL signalrail.fixture="alternate-49"\n')
VARIANT
docker build --network=none -t "$REGISTRY/parcel:stable" variant-context >/dev/null
docker push "$REGISTRY/parcel:stable" >/dev/null
printf 'intended=%s\nmutable=%s\n' "$PRIVATE_IMAGE" "$REGISTRY/parcel:stable" > release-catalog.txt
kubectl create secret docker-registry registry-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD" --dry-run=client -o json > registry-pull.json
kubectl apply -f registry-pull.json >/dev/null
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
            "image": "__CURRENT_IMAGE__",
            "imagePullPolicy": "Always",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-49\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
python3 - board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'DIGEST'
import os
from pathlib import Path
p=Path('board.json');p.write_text(p.read_text().replace('__CURRENT_IMAGE__',os.environ['REGISTRY']+'/parcel:stable'))
DIGEST
kubectl apply -f board.json
kubectl rollout status deployment/board --timeout=90s
