set -euo pipefail
cd ~/quest
test "$(kubectl exec deployment/relay -- printenv ROUTE)" = north
