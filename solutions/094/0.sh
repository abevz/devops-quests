set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "mkdir -p /tmp/site; printf \"%s\\n\" \"north-94\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"]}]'
kubectl rollout status deployment/board --timeout=60s
