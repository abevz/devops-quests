set -euo pipefail
cd ~/quest
deadline=$((SECONDS+12))
for host in app1 app2 app3; do
  peer="$host-${DQ_NAMESPACE#dq-}"
  until ssh -n -o BatchMode=yes -o ConnectTimeout=1 -o ConnectionAttempts=1 -p 2222 "root@$peer" true 2>/dev/null; do
    [ "$SECONDS" -lt "$deadline" ] || exit 1
    sleep 0.2
  done
done
for host in app2 app3; do
  ssh -n -o BatchMode=yes -p 2222 "root@$host-${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" release-60 > /srv/site/message; chmod 0644 /srv/site/message'
done
ssh -n -o BatchMode=yes -p 2222 "root@app3-${DQ_NAMESPACE#dq-}" 'dq-service reload'
deadline=$((SECONDS+12))
until test "$(curl -fsS --max-time 2 "http://app3-${DQ_NAMESPACE#dq-}:8080/" 2>/dev/null)" = release-60; do
  [ "$SECONDS" -lt "$deadline" ] || exit 1
  sleep 0.2
done
ssh -n -o BatchMode=yes -p 2222 "root@app3-${DQ_NAMESPACE#dq-}" 'set -eu
pid=$(cat /run/quest-service.pid)
case "$pid" in ""|*[!0-9]*) exit 1 ;; esac
start=$(cut -d " " -f 22 "/proc/$pid/stat")
test -n "$start" && printf "%s:%s\n" "$pid" "$start"' > healthy-service
cat > service-interface.json <<'DQ_INTERFACE'
{
  "httpPort": 8080,
  "configuration": "/srv/site/message",
  "configLoadedAt": "process-start",
  "reload": ["dq-service", "reload"]
}
DQ_INTERFACE
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'retired

        '
      mode: '0644'
DQ_ASSET
