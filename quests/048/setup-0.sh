set -euo pipefail
cd ~/quest
cat > issue-token.sh <<'DQ_ASSET'
#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
umask 077
curl -fsS -X POST -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @issue-request.json "$VAULT_ADDR/v1/auth/token/create/rail-station" | jq -er .auth.client_token > station-token
chmod 600 station-token
DQ_ASSET
cat > renew-token.sh <<'DQ_ASSET'
#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
token=$(cat station-token)
curl -fsS -X POST -H "X-Vault-Token: $token" -H 'Content-Type: application/json' --data-binary @renew-request.json "$VAULT_ADDR/v1/auth/token/renew-self" | jq -e '.auth.renewable==true' >/dev/null
DQ_ASSET
cat > issue-request.json <<'DQ_ASSET'
{"policies": ["rail-reader"], "ttl": "60s", "renewable": true, "explicit_max_ttl": "600s"}
DQ_ASSET
cat > renew-request.json <<'DQ_ASSET'
{"increment": "10s"}
DQ_ASSET
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
              "sh",
              "-c",
              "printf \"%s\" \"$ROUTE\" > /tmp/route; exec sleep 3600"
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
                  "secretKeyRef": {
                    "name": "route-secret",
                    "key": "value"
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
python3 - reader.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f reader.json
