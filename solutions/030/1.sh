set -euo pipefail
cd ~/quest
kubectl set env deployment/relay RELEASE="$(cat release.txt)"
kubectl patch service relay --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}]'
kubectl rollout status deployment/relay --timeout=90s
for i in $(seq 1 15); do
  response=$(timeout 4s kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://relay:8080/ 2>/dev/null) || response=
  if [ "$response" = signalrail ]; then
    exit 0
  fi
  sleep 1
done
printf '%s\n' 'The relay Service failed to converge' >&2
exit 1
