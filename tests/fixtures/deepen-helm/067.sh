set -euo pipefail
cd ~/quest
helm upgrade board ./chart --reuse-values --set readinessPort=8080 --wait --timeout=90s
