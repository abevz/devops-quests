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
      mode: '0755'
  - name: Restore station banner
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-79

        '
      mode: '0644'
    notify: Reload banner
  - name: Write station route
    ansible.builtin.copy:
      dest: /srv/site/config/route
      content: 'route=north

        '
      mode: '0644'
DQ_ASSET
ansible-playbook rollout.yml > repair.log
ansible-playbook rollout.yml > second.log
