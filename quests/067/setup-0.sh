set -euo pipefail
cd ~/quest
mkdir -p chart
cat > chart/Chart.yaml <<'DQ_ASSET'
apiVersion: v2
name: station-board
version: 0.1.0
DQ_ASSET
mkdir -p chart/templates
cat > chart/templates/board.yaml <<'DQ_ASSET'
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
            "image": "{{ .Values.image }}",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-67\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
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
                "port": {{ .Values.readinessPort }}
              },
              "initialDelaySeconds": 1,
              "periodSeconds": 1
            }
          }
        ]
      }
    }
  }
}
DQ_ASSET
printf 'image: %s
readinessPort: 8080
' "$DQ_APP_IMAGE" > chart/values.yaml
helm install board ./chart --wait --timeout=90s
kubectl get deployment board -o jsonpath='{.metadata.uid}' > original-deployment-uid
helm upgrade board ./chart --reuse-values --set readinessPort=9090
