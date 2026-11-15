set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Recover a rejected source before propagating
  hosts: app1
  gather_facts: false
  vars:
    trusted_previous: f5c7d9bf0eab8e9144f7c8716cccf61839dc53d39841c823cc63e075724cf7a1
  handlers:
  - name: Refresh root publisher response
    listen: Refresh publication
    ansible.builtin.command:
      argv:
      - dq-service
      - reload
  - name: Refresh supplied publication
    listen: Refresh publication
    ansible.builtin.command:
      argv:
      - runuser
      - -u
      - publication-app
      - --
      - /bin/kill
      - -HUP
      - '{{ supplied_pid.content | b64decode | trim }}'
  tasks:
  - name: Read existing application identity
    ansible.builtin.slurp:
      src: /run/propagation-consumer.pid
    register: supplied_pid
    changed_when: false
  - name: Observe controller backup hash
    ansible.builtin.stat:
      path: '{{ playbook_dir }}/previous.txt'
      checksum_algorithm: sha256
    delegate_to: localhost
    register: previous_observation
  - name: Establish recovery trust before mutation
    ansible.builtin.assert:
      that:
      - previous_observation.stat.checksum == trusted_previous
  - name: Attempt candidate and recover actual source
    block:
    - name: Deliver attempted publication
      ansible.builtin.copy:
        src: candidate.txt
        dest: /srv/site/message
        mode: '0644'
      notify: Refresh publication
    - ansible.builtin.meta: flush_handlers
    - &id001
      name: Validate actual publication consumer
      ansible.builtin.uri:
        url: http://127.0.0.1:8081/
        status_code: 200
        use_proxy: false
    rescue:
    - name: Recover trusted publication
      ansible.builtin.copy:
        src: previous.txt
        dest: /srv/site/message
        mode: '0644'
      notify: Refresh publication
    - ansible.builtin.meta: flush_handlers
    - *id001
- name: Propagate approved publication to existing consumers
  hosts: app2,app3
  gather_facts: false
  vars:
    publisher_url: http://app1-{{ lookup('env', 'DQ_NAMESPACE') | regex_replace('^dq-',
      '') }}:8081/
  tasks:
  - name: Read original application identity
    ansible.builtin.slurp:
      src: /run/propagation-consumer.pid
    register: supplied_pid
    changed_when: false
  - name: Deliver recovered legacy banner
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'stable-ready

        '
      mode: '0644'
    notify: Refresh legacy response
  - name: Connect consumer to the publication interface
    ansible.builtin.copy:
      dest: /srv/site/application.json
      content: '{{ {''upstream'': publisher_url} | to_json }}

        '
      mode: '0644'
    notify: Refresh supplied consumer
  handlers:
  - name: Refresh legacy response
    ansible.builtin.command:
      argv:
      - dq-service
      - reload
  - name: Refresh supplied consumer
    ansible.builtin.command:
      argv:
      - runuser
      - -u
      - publication-app
      - --
      - /bin/kill
      - -HUP
      - '{{ supplied_pid.content | b64decode | trim }}'
DQ_ASSET
ansible-playbook rollout.yml > recovery.log
