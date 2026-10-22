set -euo pipefail
cd ~/quest
python3 - <<'ARCHIVE'
import io,tarfile,hashlib
from pathlib import Path
with tarfile.open('recovery.tar','w') as t:
 data=b'north-96\n';i=tarfile.TarInfo('message');i.size=len(data);i.mode=0o644;i.uid=i.gid=0;t.addfile(i,io.BytesIO(data))
Path('artifact.sha256').write_text(hashlib.sha256(Path('recovery.tar').read_bytes()).hexdigest()+'\n')
ARCHIVE
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  vars:
    expected_sha256: 0000000000000000000000000000000000000000000000000000000000000000
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
      dest: /srv/site
      owner: root
      group: root
      mode: '0644'
    notify: Reload station
DQ_ASSET
