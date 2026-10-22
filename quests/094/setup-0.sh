set -euo pipefail
cd ~/quest
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
        "terminationGracePeriodSeconds": 1,
        "containers": [
          {
            "name": "worker",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-94\" > /tmp/site/index.html; while :; do :; done & exec httpd -f -p 8080 -h /tmp/site"
            ],
            "readinessProbe": {"httpGet":{"path":"/","port":8080},"periodSeconds":1},
            "resources": {
              "requests": {
                "cpu": "50m",
                "memory": "8Mi"
              },
              "limits": {
                "cpu": "50m",
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
cat > measure.sh <<'DQ_ASSET'
#!/bin/bash
set -euo pipefail
cd ~/quest
pod=$(kubectl get pods -l app=board -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null)][0].metadata.name')
# Read within one exec: launching a separate reader spends this container's CPU quota.
kubectl exec "$pod" -- sh -c '
read_counter() {
 while read -r key value rest; do
  if test "$key" = nr_throttled; then printf "%s\n" "$value"; return; fi
 done < /sys/fs/cgroup/cpu.stat
 return 1
}
before=$(read_counter)
sleep 2
after=$(read_counter)
printf "%s\n" "$((after-before))"
'
DQ_ASSET
kubectl rollout status deployment/board --timeout=60s
bash measure.sh > initial-throttled
test "$(cat initial-throttled)" -ge 10
