set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  vars:
    expected_sha256: '0000000000000000000000000000000000000000000000000000000000000000'
    restore_root: /srv/site
    restore_owner: root
    restore_group: root
  handlers:
  - name: Reload station
    ansible.builtin.command: dq-service reload
    changed_when: true
  serial: 1
  tasks:
  - name: Hash the supplied archive
    ansible.builtin.stat:
      path: '{{ playbook_dir }}/recovery.tar'
      checksum_algorithm: sha256
    delegate_to: localhost
    run_once: true
    register: artifact
  - name: Reject an unverified archive
    ansible.builtin.assert:
      that:
      - artifact.stat.checksum == expected_sha256
    run_once: true
  - name: Restore the verified board
    ansible.builtin.unarchive:
      src: recovery.tar
      dest: '{{ restore_root }}'
      owner: '{{ restore_owner }}'
      group: '{{ restore_group }}'
      mode: '0644'
      include:
      - message
    notify: Reload station
DQ_ASSET
set -euo pipefail
cd ~/quest
python3 - <<'FIX'
from pathlib import Path
p=Path('rollout.yml');p.write_text(p.read_text().replace('0'*64,Path('/run/dq/facts/0/artifact.sha256').read_text().strip()))
FIX
ansible-playbook rollout.yml
