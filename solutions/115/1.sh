set -euo pipefail
cd ~/quest
kubectl patch deployment blue --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"release":"board"}}}}}'
kubectl patch deployment green --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"release":"board"}}}}}'
kubectl patch service board --type=json -p '[{"op":"replace","path":"/spec/selector","value":{"release":"board"}}]'
kubectl scale deployment blue --replicas=3
kubectl scale deployment green --replicas=1
kubectl rollout status deployment/blue --timeout=90s
kubectl rollout status deployment/green --timeout=90s
# Rollout readiness can precede removal of terminating Pod IPs.
for i in $(seq 1 60); do
 if kubectl get pods -l 'app in (blue,green)' -o json | jq -e 'all(.items[]; .metadata.deletionTimestamp==null)' >/dev/null; then break; fi
 sleep 1
done
kubectl get pods -l 'app in (blue,green)' -o json | jq -e 'all(.items[]; .metadata.deletionTimestamp==null)' >/dev/null
