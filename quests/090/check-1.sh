set -euo pipefail
cd ~/quest
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'actual=$(sha256sum /srv/site/message 2>/dev/null | cut -d " " -f 1); if test "$actual" = 2c26e5e7347924bc4a8bab2268a1ee392c9ad6dffd932f8c400703df102f851c || test "$actual" = 5915cb21bb1ee7653775dad5a2dbfc324c46bb047d227b6e8f2e486c0961bf9d; then printf "content-ok\n"; fi; if test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then
    printf '%s\n' "$host /srv/site/message = release-90: ✗ [DQ:content_$n]"; failed=1
  fi
  if ! grep -Fxq mode-ok <<<"$result"; then
    printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1
  fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = release-90; then
    printf '%s\n' "$host:8080 = release-90: ✗ [DQ:http_$n]"; failed=1
  fi
done
exit "$failed"
