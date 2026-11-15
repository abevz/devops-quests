set -euo pipefail
cd ~/quest
kubectl patch job importer --type=merge -p '{"spec":{"backoffLimit":1,"activeDeadlineSeconds":30}}'
kubectl wait --for=condition=Failed job/importer --timeout=60s
