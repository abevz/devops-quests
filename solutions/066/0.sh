set -euo pipefail
cd ~/quest
jq --slurpfile c /run/dq/facts/0/release-catalog.json '{delete:[$c[0].obsolete]}' retention.json > corrected-retention.json
mv corrected-retention.json retention.json
bash prune.sh
