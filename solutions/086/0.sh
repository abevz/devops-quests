set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Attempt release and recover
    block:
    - name: Deliver the route message
      ansible.builtin.copy:
        dest: /srv/site/message
        content: 'candidate

          '
        mode: '0644'
    - name: Validate candidate
      ansible.builtin.command: /bin/false
    rescue:
    - name: Deliver the route message
      ansible.builtin.copy:
        dest: /srv/site/message
        content: 'stable-ready

          '
        mode: '0644'
      notify: Reload banner
DQ_ASSET
ansible-playbook rollout.yml
