set -euo pipefail
source platform.env
cat > deployment.json <<'DQ_ASSET'
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
            "image": "PRIVATE_IMAGE_PLACEHOLDER",
            "imagePullPolicy": "Always",
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
                "memory": "64Mi"
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
sed -i "s|PRIVATE_IMAGE_PLACEHOLDER|$PRIVATE_IMAGE|g" deployment.json
kubectl apply -f deployment.json
