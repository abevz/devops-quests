set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Write fleet summary
    ansible.builtin.copy:
      dest: '{{ playbook_dir }}/fleet.txt'
      content: '{{ inventory_hostname }}

        '
      mode: '0644'
    delegate_to: localhost
DQ_ASSET
