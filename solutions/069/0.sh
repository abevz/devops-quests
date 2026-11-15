set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_PROVIDED'
- name: Deliver private inputs to their provided consumers
  hosts: fleet
  gather_facts: false
  vars_files:
  - credentials.yml
  tasks:
  - name: Prepare private data before ownership transfer
    ansible.builtin.copy:
      dest: '{{ item.path }}'
      content: '{{ station_token }}

        '
      mode: '0600'
    loop: &id001
    - name: credential-a
      uid: 1001
      path: /srv/site/station-token
      port: 8081
    - name: credential-b
      uid: 1002
      path: /srv/relay/station-token
      port: 8082
    no_log: true
  - name: Transfer private input to its recipient
    ansible.builtin.file:
      path: '{{ item.path }}'
      owner: '{{ item.name }}'
      group: '{{ item.name }}'
    loop: *id001
DQ_PROVIDED
ansible-playbook --diff rollout.yml > deployment.log
