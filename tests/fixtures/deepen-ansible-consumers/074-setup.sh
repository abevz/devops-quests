set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" previous-74 > /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" previous-74 > /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" previous-74 > /srv/site/message; dq-service reload'
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Deliver inspected release
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-74

        '
      mode: '0644'
    notify: Reload banner
  - name: Inspect live process
    ansible.builtin.command: cat /run/quest-service.pid
    changed_when: false
DQ_ASSET
