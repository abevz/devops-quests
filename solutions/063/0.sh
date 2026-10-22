set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  serial: 1
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Attempt candidate and restore stable artifact
    block:
    - name: Install candidate
      ansible.builtin.copy:
        src: candidate.txt
        dest: /srv/site/message
        mode: '0644'
    - name: Validate candidate
      ansible.builtin.command: grep -qx approved /srv/site/message
      changed_when: false
    rescue:
    - name: Restore verified previous artifact
      ansible.builtin.copy:
        src: previous.txt
        dest: /srv/site/message
        mode: '0644'
      notify: Reload banner
    always:
    - name: Record completed recovery check
      ansible.builtin.copy:
        dest: /srv/site/recovery-checked
        content: 'checked

          '
        mode: '0644'
DQ_ASSET
sha256sum -c previous.sha256
ansible-playbook rollout.yml
