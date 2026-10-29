set -euo pipefail
cd ~/quest
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'value=$(cat /srv/site/message 2>/dev/null || true); mode=$(stat -c %a /srv/site/message 2>/dev/null || true); if test "$value" = release-20; then printf "content-ok\n"; fi; if test "$mode" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = release-20: ✗ [DQ:content_$n]"; failed=1; fi
  if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1; fi
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = release-20; then
    printf '%s\n' "$host:8080 = release-20: ✗ [DQ:http_$n]"; failed=1
  fi
done
if ! ANSIBLE_NOCOLOR=1 ansible-playbook rollout.yml > second-run.txt 2>&1; then printf '%s\n' 'second ansible-playbook rollout.yml succeeds: ✗ [DQ:rerun]'; failed=1; fi
for n in 1 2 3; do
  for field in changed failed; do
    if ! grep -Eq "^app${n}[[:space:]]+:.*[[:space:]]${field}=0([[:space:]]|$)" second-run.txt; then
      printf '%s\n' "app$n second recap $field = 0: ✗ [DQ:recap_${n}_${field}]"; failed=1
    fi
  done
done
exit "$failed"
