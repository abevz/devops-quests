set -euo pipefail
cd ~/quest
expected=$(jq -er .release_id /run/dq/facts/0/recovery-contract.json)
recovery_id=$(tofu output -raw recovery_id)
test "$expected" = "$recovery_id"
jq -n --arg release "$(cat release.txt)" --arg recovery_id "$recovery_id" \
  '{release:$release,recovery_id:$recovery_id}' > recovered-release.json
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'retired

        '
      mode: '0644'
DQ_ASSET
