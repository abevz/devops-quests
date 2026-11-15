set -euo pipefail
cd ~/quest
cat > message.j2 <<'DQ_TEMPLATE'
station={{ station.name }}
route={{ station.route }}
DQ_TEMPLATE
cat > route-declarations.yml <<'DQ_INPUTS'
station_routes:
  app1: {active: north}
  app2: {active: north}
  app3: {active: north}
DQ_INPUTS
cat > rollout.yml <<'DQ_PLAY'
- name: Render station route inputs
  hosts: fleet
  gather_facts: false
  vars_files:
  - route-declarations.yml
  tasks:
  - name: Render each station banner
    ansible.builtin.template:
      src: message.j2
      dest: /srv/site/message
      mode: '0644'
DQ_PLAY
cat > template-contract.json <<'DQ_CONTRACT'
{
  "schema": 1,
  "template": "message.j2",
  "routeInputFile": "route-declarations.yml",
  "hostContext": "normal Ansible inventory host context",
  "routeInputShape": "station_routes maps host names to records with active routes",
  "requiredOutput": "complete station and route lines for the current caller inputs",
  "cases": {
    "probe-a": "south",
    "probe-b": "east",
    "probe-c": "north"
  },
  "preserveManagedHostResults": true,
  "observesCurrentProgramCapabilityOnly": true
}
DQ_CONTRACT
