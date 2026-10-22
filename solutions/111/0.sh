set -euo pipefail
cd ~/quest
kubectl patch statefulset shelf --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "exec httpd -f -p 8080 -h /data"]}]'
kubectl rollout status statefulset/shelf --timeout=90s
