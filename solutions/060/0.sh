set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Recover and verify the fleet release
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Observe the running release
    ansible.builtin.uri:
      url: http://127.0.0.1:8080/
      return_content: true
      timeout: 2
    register: running_release
    failed_when: false
  - name: Deliver release bytes
    ansible.builtin.copy:
      dest: /srv/site/message
      content: |
        release-60
      mode: '0644'
    register: publication
    notify: Reload banner
  - name: Refresh a stale process even when the file is unchanged
    ansible.builtin.command:
      argv: [dq-service, reload]
    when: not publication.changed and (running_release.content | default('') | trim != 'release-60')
  handlers:
  - name: Reload banner
    ansible.builtin.command:
      argv: [dq-service, reload]
  post_tasks:
  - name: Verify the current service reply
    ansible.builtin.uri:
      url: http://127.0.0.1:8080/
      return_content: true
    register: response
    until: response.status == 200 and response.content | trim == 'release-60'
    retries: 5
    delay: 1
DQ_ASSET
ansible-playbook rollout.yml
