set -euo pipefail
cd ~/quest
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'actual=$(sha256sum /srv/site/message 2>/dev/null | cut -d " " -f 1); if test "$actual" = 679654d8c0b2d19d0c05fa59f6830658bb6dcbf0e0872a66360ad0b032813982 || test "$actual" = facfe2047ac974e0f4348307cc1a8a543df489b6c451b5fbb3de2d546a89f0cb; then printf "content-ok\n"; fi; if test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then
    printf '%s\n' "$host /srv/site/message = release-81: ✗ [DQ:content_$n]"; failed=1
  fi
  if ! grep -Fxq mode-ok <<<"$result"; then
    printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1
  fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = release-81; then
    printf '%s\n' "$host:8080 = release-81: ✗ [DQ:http_$n]"; failed=1
  fi
done
exit "$failed"
