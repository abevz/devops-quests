set -euo pipefail
cd ~/quest
kubectl get endpointslices -l kubernetes.io/service-name=arrivals -o json | jq -e 'any(.items[].endpoints[]?; .conditions.ready==true)' >/dev/null
