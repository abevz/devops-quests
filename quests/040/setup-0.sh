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
    "replicas": 2,
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
              "mkdir -p /tmp/site; printf \"%s\\n\" \"retired\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
            "readinessProbe": {
              "httpGet": {
                "path": "/",
                "port": 8080
              },
              "periodSeconds": 1
            }
          }
        ]
      }
    },
    "strategy": {
      "type": "RollingUpdate",
      "rollingUpdate": {
        "maxUnavailable": 0,
        "maxSurge": 1
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
kubectl rollout status deployment/board --timeout=60s
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  serial: 1
  tasks:
  - name: Deliver maintenance contract
    ansible.builtin.copy:
      dest: /srv/site/maintenance.txt
      content: 'retired

        '
      mode: '0644'
DQ_ASSET
