set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Write private reader credential
    ansible.builtin.copy:
      dest: /srv/site/reader.token
      content: 'game-only-reader

        '
      mode: '0600'
    no_log: true
  - name: Deliver verified manifest
    ansible.builtin.copy:
      src: release.txt
      dest: /srv/site/release.txt
      mode: '0644'
DQ_ASSET
ansible-playbook rollout.yml
cat > release.txt <<'DQ_ASSET'
release-89
DQ_ASSET
ansible-playbook rollout.yml
