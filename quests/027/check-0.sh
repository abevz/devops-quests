set -euo pipefail
cd ~/quest
kubectl rollout status deployment/relay --timeout=3s >/dev/null
kubectl get deployment relay -o json | jq -e '.spec.template.spec.containers[0].imagePullPolicy=="Always" and (.spec.template.spec.imagePullSecrets|length)>0' >/dev/null
