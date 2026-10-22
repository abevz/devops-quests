set -euo pipefail
cd ~/quest
cat > terraform.tfvars <<'DQ_ASSET'
routes = { north = "open", south = "held", east = "open" }
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
