set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "mkdir -p /tmp/site; printf \"%s\\n\" \"north-102-v3\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"]}, {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": 8099}]'
