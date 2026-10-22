set -euo pipefail
cd ~/quest
cat > reader.hcl <<'DQ_ASSET'
path "secret/data/dispatch" { capabilities = ["read"] }
DQ_ASSET
bash apply-policy.sh
