set -euo pipefail
cd ~/quest
cat > cronjob.json <<'DQ_ASSET'
{
  "apiVersion": "batch/v1",
  "kind": "CronJob",
  "metadata": {
    "name": "route-audit"
  },
  "spec": {
    "schedule": "* * * * *",
    "timeZone": "Etc/UTC",
    "suspend": true,
    "concurrencyPolicy": "Allow",
    "startingDeadlineSeconds": 20,
    "successfulJobsHistoryLimit": 1,
    "failedJobsHistoryLimit": 1,
    "jobTemplate": {
      "spec": {
        "backoffLimit": 0,
        "activeDeadlineSeconds": 20,
        "template": {
          "metadata": {
            "labels": {
              "app": "route-audit"
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
                  "printf \"%s\\n\" north-104"
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
  }
}
DQ_ASSET
python3 - cronjob.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f cronjob.json
