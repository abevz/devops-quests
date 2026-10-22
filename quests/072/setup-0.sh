set -euo pipefail
cd ~/quest
cat > job.json <<'DQ_ASSET'
{
  "apiVersion": "batch/v1",
  "kind": "Job",
  "metadata": {
    "name": "importer"
  },
  "spec": {
    "backoffLimit": 100,
    "activeDeadlineSeconds": 300,
    "parallelism": 1,
    "completions": 1,
    "template": {
      "metadata": {
        "labels": {
          "app": "importer"
        }
      },
      "spec": {
        "restartPolicy": "Never",
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
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "echo invalid-route >&2; exit 1"
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
        ]
      }
    }
  }
}
DQ_ASSET
python3 - job.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f job.json
kubectl get job importer -o jsonpath='{.metadata.uid}' > original-job-uid
