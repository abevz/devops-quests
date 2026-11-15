set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Deliver to both existing application consumers
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Read existing application identity
    ansible.builtin.slurp:
      src: /run/quest-banner-reader.pid
    register: provided_pid
    changed_when: false
  - name: Deliver shared message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-ready

        '
      mode: '0644'
    notify: Refresh consumers
  handlers:
  - name: Refresh root application
    listen: Refresh consumers
    ansible.builtin.command:
      argv:
      - dq-service
      - reload
  - name: Refresh provided application as its principal
    listen: Refresh consumers
    ansible.builtin.command:
      argv:
      - runuser
      - -u
      - banner-reader
      - --
      - /bin/kill
      - -HUP
      - '{{ provided_pid.content | b64decode | trim }}'
DQ_ASSET
ansible-playbook rollout.yml
