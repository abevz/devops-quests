set -euo pipefail
cd ~/quest
cat > fixed.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "relay"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "relay"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "relay"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "${DQ_APP_IMAGE}",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/www; echo signalrail >/tmp/www/index.html; httpd -f -p 8080 -h /tmp/www"
            ],
            "ports": [
              {
                "containerPort": 8080
              }
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "16Mi"
              },
              "limits": {
                "memory": "96Mi"
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
                "port": 8080,
                "path": "/"
              },
              "periodSeconds": 2
            }
          }
        ]
      }
    }
  }
}
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' fixed.json
kubectl apply -f fixed.json
kubectl rollout status deployment/relay --timeout=90s
