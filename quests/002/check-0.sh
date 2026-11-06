set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
n=1
host="app${n}-${DQ_NAMESPACE#dq-}"
result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = north-ready; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = north-ready: ✗ [DQ:content_$n]"; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
n=1
host="app${n}-${DQ_NAMESPACE#dq-}"
result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = north-ready; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
n=2
host="app${n}-${DQ_NAMESPACE#dq-}"
result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = north-ready; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = north-ready: ✗ [DQ:content_$n]"; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
n=2
host="app${n}-${DQ_NAMESPACE#dq-}"
result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = north-ready; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
n=3
host="app${n}-${DQ_NAMESPACE#dq-}"
result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = north-ready; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = north-ready: ✗ [DQ:content_$n]"; exit 1; fi
)
[ $? -eq 0 ] || failed=1
(
set -e
n=3
host="app${n}-${DQ_NAMESPACE#dq-}"
result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = north-ready; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; exit 1; fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
