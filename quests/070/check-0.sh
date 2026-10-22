set -euo pipefail
cd ~/quest
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.spec.source.path=="manifests" and .status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].env==[{name:"ROUTE_SECRET",valueFrom:{secretKeyRef:{name:"route-secret",key:"value"}}}]' >/dev/null
