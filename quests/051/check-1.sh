set -euo pipefail
cd ~/quest
test "$(kubectl exec deployment/backup -- printenv ROUTE)" = north
