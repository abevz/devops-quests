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
      content: '{% for host in groups["fleet"] | sort %}{{ host }}

        {% endfor %}'
      mode: '0644'
    delegate_to: localhost
    run_once: true
DQ_ASSET
ansible-playbook rollout.yml
