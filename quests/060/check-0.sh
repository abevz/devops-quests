set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = release-60 && test "$(stat -c %a /srv/site/message)" = 644'; then printf '%s\n' 'app1 file release-60: ✗ [DQ:file_1]' >&2; failed=1; fi
if ! ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = release-60 && test "$(stat -c %a /srv/site/message)" = 644'; then printf '%s\n' 'app2 file release-60: ✗ [DQ:file_2]' >&2; failed=1; fi
if ! ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = release-60 && test "$(stat -c %a /srv/site/message)" = 644'; then printf '%s\n' 'app3 file release-60: ✗ [DQ:file_3]' >&2; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(curl -fsS --max-time 3 http://app1-${DQ_NAMESPACE#dq-}:8080)" = release-60; then printf '%s\n' 'app1 http release-60: ✗ [DQ:http_1]' >&2; failed=1; fi
if ! test "$(curl -fsS --max-time 3 http://app2-${DQ_NAMESPACE#dq-}:8080)" = release-60; then printf '%s\n' 'app2 http release-60: ✗ [DQ:http_2]' >&2; failed=1; fi
if ! test "$(curl -fsS --max-time 3 http://app3-${DQ_NAMESPACE#dq-}:8080)" = release-60; then printf '%s\n' 'app3 http release-60: ✗ [DQ:http_3]' >&2; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
