set -euo pipefail
cd ~/quest
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); printf "%s\n%s\n" "$value" "$mode"' 2>/dev/null || true)
  if ! test "$(printf '%s\n' "$result" | sed -n '1p')" = release-90; then
    printf '%s\n' "$host /srv/site/message = release-90: ✗"; failed=1
  fi
  if ! test "$(printf '%s\n' "$result" | sed -n '2p')" = 644; then
    printf '%s\n' "$host /srv/site/message mode = 644: ✗"; failed=1
  fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = release-90; then
    printf '%s\n' "$host:8080 = release-90: ✗"; failed=1
  fi
done
exit "$failed"
