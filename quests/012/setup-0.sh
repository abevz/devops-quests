set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Record the managed platform
    ansible.builtin.copy:
      dest: /srv/site/facts.json
      content: '{{ {"family": ansible_facts.os_family, "architecture": ansible_facts.architecture}
        | to_json }}

        '
      mode: '0644'
DQ_ASSET
