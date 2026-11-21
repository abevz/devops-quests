set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Deliver and activate the maintenance handover
  hosts: fleet
  gather_facts: false
  serial: 1
  tasks:
  - name: Deliver maintenance contract
    ansible.builtin.copy:
      dest: /srv/site/maintenance.txt
      content: |
        north-40
      mode: '0644'
  - name: Publish station message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: |
        north-40
      mode: '0644'
    notify: Reload station service
  handlers:
  - name: Reload station service
    ansible.builtin.command:
      argv: [dq-service, reload]
  post_tasks:
  - name: Verify station message before the next batch
    ansible.builtin.uri:
      url: http://127.0.0.1:8080/
      return_content: true
    register: station_response
    until: station_response.status == 200 and station_response.content | trim == 'north-40'
    retries: 5
    delay: 1
DQ_ASSET
ansible-playbook rollout.yml
