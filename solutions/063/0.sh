set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: Recover only from verified caller input
  hosts: fleet
  gather_facts: false
  serial: 1
  vars:
    delivery_path: /srv/site/message
    candidate_path: '{{ playbook_dir }}/candidate.txt'
    previous_path: '{{ playbook_dir }}/previous.txt'
    previous_sha256: '{{ lookup(''file'', playbook_dir + ''/previous.sha256'').split()[0]
      }}'
    recovery_marker: /srv/site/recovery-checked
    service_reload:
    - dq-service
    - reload
  handlers:
  - name: Refresh actual consumer
    ansible.builtin.command:
      argv: '{{ service_reload }}'
  tasks:
  - name: Read controller backup checksum
    delegate_to: localhost
    ansible.builtin.stat:
      path: '{{ previous_path }}'
      checksum_algorithm: sha256
    register: backup_observation
  - name: Refuse an untrusted backup before mutation
    ansible.builtin.assert:
      that:
      - backup_observation.stat.checksum == previous_sha256
  - name: Attempt candidate with a verified recovery path
    block:
    - name: Install caller candidate
      ansible.builtin.copy:
        src: '{{ candidate_path }}'
        dest: '{{ delivery_path }}'
        mode: '0644'
      notify: Refresh actual consumer
    - name: Validate actual candidate
      ansible.builtin.command:
        argv:
        - grep
        - -qx
        - approved
        - '{{ delivery_path }}'
      changed_when: false
    rescue:
    - name: Restore verified backup
      ansible.builtin.copy:
        src: '{{ previous_path }}'
        dest: '{{ delivery_path }}'
        mode: '0644'
      notify: Refresh actual consumer
    always:
    - name: Record recovery check
      ansible.builtin.copy:
        dest: '{{ recovery_marker }}'
        content: 'checked

          '
        mode: '0644'
DQ_ASSET
sha256sum -c previous.sha256
ansible-playbook rollout.yml
