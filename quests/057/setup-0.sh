set -euo pipefail
cat > spool.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "PersistentVolumeClaim",
  "metadata": {
    "name": "spool"
  },
  "spec": {
    "accessModes": [
      "ReadWriteOnce"
    ],
    "storageClassName": "unknown-rail",
    "resources": {
      "requests": {
        "storage": "8Mi"
      }
    }
  }
}
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' spool.json
kubectl apply -f spool.json
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
            },
            "volumeMounts": [
              {
                "name": "spool",
                "mountPath": "/spool"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "spool",
            "persistentVolumeClaim": {
              "claimName": "spool"
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
