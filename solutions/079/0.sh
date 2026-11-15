set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- hosts: fleet
  gather_facts: false
  vars:
    delivery_root: /srv/site
    expected_message: north-79
    expected_route: route=north
    service_observe:
    - curl
    - -fsS
    - --max-time
    - '2'
    - http://127.0.0.1:8080/
    service_reload:
    - dq-service
    - reload
  tasks:
  - name: Construct configuration directory
    ansible.builtin.file:
      path: '{{ delivery_root }}/config'
      state: directory
      mode: '0755'
  - name: Deliver banner
    ansible.builtin.copy:
      dest: '{{ delivery_root }}/message'
      content: '{{ expected_message }}

        '
      mode: '0644'
    notify: Refresh consumer
  - name: Deliver route
    ansible.builtin.copy:
      dest: '{{ delivery_root }}/config/route'
      content: '{{ expected_route }}

        '
      mode: '0644'
    notify: Refresh consumer
  - name: Observe actual consumer
    ansible.builtin.command:
      argv: '{{ service_observe }}'
    register: consumer_observation
    changed_when: false
  - name: Recover stale live state even without a file change
    ansible.builtin.command:
      argv: '{{ service_reload }}'
    when: consumer_observation.stdout | trim != expected_message
  handlers:
  - name: Refresh consumer
    ansible.builtin.command:
      argv: '{{ service_reload }}'
DQ_ASSET
ansible-playbook rollout.yml > repair.log
ansible-playbook rollout.yml > second.log
