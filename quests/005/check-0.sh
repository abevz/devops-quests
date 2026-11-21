set -euo pipefail
cd ~/quest
status=0
for host in 1 2 3; do
  ssh -n -o BatchMode=yes -p 2222 root@app"$host"-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644' || {
    code=$?
    printf '%s\n' "app$host message content and mode: ✗ [DQ:copy_$host]" >&2
    if [ "$status" -eq 0 ]; then
      status=$code
    fi
  }
done
exit "$status"
