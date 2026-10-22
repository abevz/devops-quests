set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" north-46 > /srv/site/banner.txt'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" north-46 > /srv/site/banner.txt'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" north-46 > /srv/site/banner.txt'
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deploy a replacement banner
    ansible.builtin.copy:
      dest: /srv/site/banner.txt
      content: 'retired

        '
      mode: '0644'
    tags:
    - inspect
  - name: Inspect the current banner
    ansible.builtin.stat:
      path: /srv/site/banner.txt
    tags:
    - inspect
DQ_ASSET
