set -euo pipefail
cd ~/quest
cat > previous.txt <<'DQ_ASSET'
stable-63
DQ_ASSET
cat > candidate.txt <<'DQ_ASSET'
unapproved-candidate
DQ_ASSET
sha256sum previous.txt > previous.sha256
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" interrupted-63 > /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" interrupted-63 > /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" interrupted-63 > /srv/site/message; dq-service reload'
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
    - name: Report missing rollback
      ansible.builtin.debug:
        msg: Rollback not configured
    always:
    - name: Record completed recovery check
      ansible.builtin.copy:
        dest: /srv/site/recovery-checked
        content: 'checked

          '
        mode: '0644'
DQ_ASSET
