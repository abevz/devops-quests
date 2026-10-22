set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Create station configuration directory
    ansible.builtin.file:
      path: /srv/site/config
      state: directory
      mode: '0700'
  - name: Restore station banner
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-79

        '
      mode: '0600'
    notify: Reload banner
  - name: Write station route
    ansible.builtin.copy:
      dest: /srv/site/config/route
      content: 'route=north

        '
      mode: '0644'
DQ_ASSET
ssh -n -o BatchMode=yes -p 2222 root@app1-${DQ_NAMESPACE#dq-} 'set -eu; mkdir -p /srv/site/config; chmod 755 /srv/site/config; printf "%s\n" north-79 > /srv/site/message; chmod 644 /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app2-${DQ_NAMESPACE#dq-} 'set -eu; mkdir -p /srv/site/config; chmod 700 /srv/site/config; printf "%s\n" retired-79 > /srv/site/message; chmod 600 /srv/site/message; dq-service reload'
