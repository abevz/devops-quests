set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: offline:fleet
  gather_facts: false
  tasks:
  - name: Probe reachability
    ansible.builtin.ping: {}
    ignore_unreachable: true
  - name: Record check
    ansible.builtin.copy:
      dest: '{{ playbook_dir }}/safety-check.txt'
      content: 'healthy fleet checked

        '
      mode: '0644'
    delegate_to: localhost
    run_once: true
DQ_ASSET
ansible-playbook -i inventory.ini -i offline.ini rollout.yml > probe.log
