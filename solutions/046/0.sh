set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deploy a replacement banner
    ansible.builtin.copy:
      dest: /srv/site/banner.txt
      content: 'retired

        '
      mode: '0644'
    tags:
    - deploy
  - name: Inspect the current banner
    ansible.builtin.stat:
      path: /srv/site/banner.txt
    tags:
    - inspect
DQ_ASSET
ansible-playbook --tags inspect rollout.yml > inspection.log
