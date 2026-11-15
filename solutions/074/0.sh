set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Deliver caller release with truthful preview
  hosts: fleet
  gather_facts: false
  vars:
    delivery_path: /srv/site/message
    release_text: north-74
    inspection_path: /run/quest-service.pid
    service_reload:
    - dq-service
    - reload
  handlers:
  - name: Refresh provided consumer
    ansible.builtin.command:
      argv: '{{ service_reload }}'
  tasks:
  - name: Deliver declared release
    ansible.builtin.copy:
      dest: '{{ delivery_path }}'
      content: '{{ release_text }}

        '
      mode: '0644'
    notify: Refresh provided consumer
  - name: Inspect current process
    ansible.builtin.command:
      argv:
      - cat
      - '{{ inspection_path }}'
    changed_when: false
DQ_ASSET
ansible-playbook --check --diff rollout.yml > check.log
ansible-playbook rollout.yml > apply.log
