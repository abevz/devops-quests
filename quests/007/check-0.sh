set -euo pipefail
cd ~/quest
test "$(kubectl exec deployment/relay -c worker -- printenv ROUTE)" = north
