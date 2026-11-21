set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Restore fleet from the recovered release
  hosts: fleet
  gather_facts: false
  vars:
    recovered: "{{ lookup('ansible.builtin.file', 'recovered-release.json') | from_json }}"
  tasks:
  - name: Deliver recovered message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: |
        {{ recovered.release }}
      mode: '0644'
    notify: Reload banner
  - name: Return recovered identity
    ansible.builtin.copy:
      dest: /srv/site/recovery-id
      content: |
        {{ recovered.recovery_id }}
      mode: '0644'
  handlers:
  - name: Reload banner
    ansible.builtin.command:
      argv: [dq-service, reload]
  post_tasks:
  - name: Verify each resumed HTTP process
    ansible.builtin.uri:
      url: http://127.0.0.1:8080/
      return_content: true
    register: observed
    until: observed.status == 200 and observed.content | trim == recovered.release
    retries: 5
    delay: 1
DQ_ASSET
ansible-playbook rollout.yml
