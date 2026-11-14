set -euo pipefail
cd ~/quest
tofu output -json delivery > delivery.json
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  vars:
    delivery: '{{ lookup("ansible.builtin.file", "delivery.json") | from_json }}'
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Deliver the current producer release
    ansible.builtin.copy:
      dest: /srv/site/message
      content: |
        {{ delivery.targets[inventory_hostname].release }}
      mode: '0644'
    notify: Reload banner
  - name: Deliver this target receipt
    ansible.builtin.copy:
      dest: /srv/site/delivery.json
      content: |
        {{ delivery.targets[inventory_hostname] | to_json }}
      mode: '0644'
DQ_ASSET
ansible-playbook rollout.yml
