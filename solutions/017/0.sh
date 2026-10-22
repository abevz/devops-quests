set -euo pipefail
cd ~/quest
cat > quarantine.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "quarantine"
  },
  "spec": {
    "replicas": 1,
    "strategy": {"type":"Recreate"},
    "selector": {
      "matchLabels": {
        "app": "quarantine"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "quarantine",
          "route-service": "departures"
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
                "value": "retired"
              }
            ],
            "readinessProbe": {
              "exec": {
                "command": [
                  "sh",
                  "-c",
                  "test \"$ROUTE\" = north"
                ]
              },
              "periodSeconds": 1,
              "failureThreshold": 1
            }
          }
        ]
      }
    }
  }
}
DQ_ASSET
python3 - quarantine.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f quarantine.json
ready=0
for _ in $(seq 1 60); do
 if kubectl get pods -l app=quarantine -o json | jq -e '
   [.items[] | select(.metadata.deletionTimestamp==null)] |
   length==1 and all(.[]; .status.phase=="Running" and
     any(.status.conditions[]; .type=="Ready" and .status=="False"))
 ' >/dev/null; then ready=1; break; fi
 sleep 1
done
test "$ready" = 1

for _ in $(seq 1 30); do
 good=$(kubectl get pods -l app=stable -o jsonpath='{.items[0].metadata.name}')
 current=$(kubectl get endpointslices -l kubernetes.io/service-name=departures -o json | jq -r '[.items[].endpoints[] | select(.conditions.ready==true) | .targetRef.name] | unique | .[]')
 test "$current" = "$good" && break
 sleep 1
done
