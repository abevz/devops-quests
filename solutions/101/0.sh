set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op":"replace","path":"/spec/template/spec/initContainers/0/command","value":["sh","-c","cp /input/route /shared/route"]}]'
kubectl rollout status deployment/board --timeout=90s
