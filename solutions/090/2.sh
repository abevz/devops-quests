set -euo pipefail
cd ~/quest
published_id=$(cat relay-handover-id)
kubectl patch configmap relay-recovery --type=merge -p "$(jq -n --arg id "$published_id" '{data:{"recovery-id":$id}}')"
kubectl set env deployment/relay RELEASE=release-90
kubectl rollout status deployment/relay --timeout=90s
deadline=$((SECONDS+100))
until test "$(timeout 5s kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://127.0.0.1:8080/recovery-id 2>/dev/null)" = "$published_id"; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    printf '%s\n' 'The relay projection did not converge to the recovered identity' >&2
    exit 1
  fi
  sleep 2
done
