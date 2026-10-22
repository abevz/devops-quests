set -euo pipefail
cd ~/quest
cat > offline.ini <<'DQ_ASSET'
[diagnostic]
offline ansible_host=127.0.0.1 ansible_port=1 ansible_connect_timeout=1
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: offline:fleet
  gather_facts: false
  tasks:
  - name: Probe reachability
    ansible.builtin.ping: {}
  - name: Record check
    ansible.builtin.copy:
      dest: '{{ playbook_dir }}/safety-check.txt'
      content: 'healthy fleet checked

        '
      mode: '0644'
    delegate_to: localhost
    run_once: true
DQ_ASSET
