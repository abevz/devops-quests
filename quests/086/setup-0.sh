set -euo pipefail
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Attempt release and recover
    block:
    - name: Deliver the route message
      ansible.builtin.copy:
        dest: /srv/site/message
        content: 'candidate

          '
        mode: '0644'
    - name: Validate candidate
      ansible.builtin.command: /bin/false
    rescue:
    - name: Record missing recovery
      ansible.builtin.debug:
        msg: Recovery was not implemented.
DQ_ASSET
