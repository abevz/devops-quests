set -euo pipefail
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
            "image": "${DQ_APP_IMAGE}",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "x=xxxxxxxx; while :; do x=$x$x; done"
            ],
            "ports": [
              {
                "containerPort": 8080
              }
            ],
            "resources": {
              "requests": {
                "memory": "16Mi"
              },
              "limits": {
                "memory": "16Mi"
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
                "port": 9090,
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
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' deployment.json
kubectl apply -f deployment.json
