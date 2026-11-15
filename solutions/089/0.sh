set -euo pipefail
cd ~/quest
cat > release.txt <<'DQ_ARTIFACT'
release-89
DQ_ARTIFACT
cat > rollout.yml <<'DQ_ASSET'
- name: Verify and activate the artifact source
  hosts: app1
  gather_facts: false
  vars_files:
  - credentials.yml
  vars:
    trusted_sha256: 2f07a87606f1ec3bd71c6968b24eef3d2ae9013071c46dbaa2611187122aced6
  tasks:
  - name: Observe actual controller artifact hash
    ansible.builtin.stat:
      path: '{{ playbook_dir }}/release.txt'
      checksum_algorithm: sha256
    delegate_to: localhost
    register: source_observation
  - name: Reject an untrusted source before delivery
    ansible.builtin.assert:
      that:
      - source_observation.stat.checksum == trusted_sha256
  - name: Read original application identity
    ansible.builtin.slurp:
      src: /run/propagation-consumer.pid
    register: supplied_pid
    changed_when: false
  - name: Deliver verified artifact
    ansible.builtin.copy:
      src: release.txt
      dest: /srv/site/release.txt
      mode: '0644'
  - name: Prepare private credential before ownership transfer
    ansible.builtin.copy:
      dest: /srv/site/reader.token
      content: '{{ reader_token }}

        '
      mode: '0600'
    no_log: true
  - name: Transfer private input to existing principal
    ansible.builtin.file:
      path: /srv/site/reader.token
      owner: publication-app
      group: publication-app
  - name: Provide publication interface input
    ansible.builtin.copy:
      dest: /srv/site/application.json
      content: '{"release_path": "/srv/site/release.txt", "sha256": "2f07a87606f1ec3bd71c6968b24eef3d2ae9013071c46dbaa2611187122aced6",
        "generation": "approved-89"}

        '
      mode: '0644'
  - name: Activate the prepared application under its original principal
    ansible.builtin.command:
      argv:
      - runuser
      - -u
      - publication-app
      - --
      - /bin/kill
      - -HUP
      - '{{ supplied_pid.content | b64decode | trim }}'
  - &id001
    name: Verify actual authenticated publication before propagation
    ansible.builtin.uri:
      url: http://127.0.0.1:8081/
      headers:
        Authorization: Bearer {{ reader_token }}
      status_code: 200
      use_proxy: false
    no_log: true
- name: Deliver private inputs and propagate from the verified source
  hosts: app2,app3
  gather_facts: false
  vars_files:
  - credentials.yml
  vars:
    publisher_url: http://app1-{{ lookup('env', 'DQ_NAMESPACE') | regex_replace('^dq-',
      '') }}:8081/
  tasks:
  - name: Read original application identity
    ansible.builtin.slurp:
      src: /run/propagation-consumer.pid
    register: supplied_pid
    changed_when: false
  - name: Deliver verified artifact
    ansible.builtin.copy:
      src: release.txt
      dest: /srv/site/release.txt
      mode: '0644'
  - name: Prepare private credential before ownership transfer
    ansible.builtin.copy:
      dest: /srv/site/reader.token
      content: '{{ reader_token }}

        '
      mode: '0600'
    no_log: true
  - name: Transfer private input to existing principal
    ansible.builtin.file:
      path: /srv/site/reader.token
      owner: publication-app
      group: publication-app
  - name: Provide publication interface input
    ansible.builtin.copy:
      dest: /srv/site/application.json
      content: '{{ {''upstream'': publisher_url} | to_json }}

        '
      mode: '0644'
  - name: Activate the prepared application under its original principal
    ansible.builtin.command:
      argv:
      - runuser
      - -u
      - publication-app
      - --
      - /bin/kill
      - -HUP
      - '{{ supplied_pid.content | b64decode | trim }}'
  - *id001
DQ_ASSET
ansible-playbook --diff rollout.yml > deployment.log
