set -euo pipefail
cd ~/quest
test "$(kubectl exec deployment/backup -c worker -- printenv ROUTE)" = north
