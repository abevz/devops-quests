set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "release" {
 filename = "${path.root}/release.txt"
 content = "retired\n"
}
output "release" { value = local_file.release.content }
DQ_ASSET
tofu init -input=false -no-color
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: relays
  gather_facts: false
  tasks:
  - name: Deliver release
    ansible.builtin.copy:
      src: release.txt
      dest: /srv/site/message
      mode: '0644'
DQ_ASSET
