set -euo pipefail
cd ~/quest
for name in board-internal board-headless board-node; do kubectl patch service "$name" --type=merge -p '{"spec":{"selector":{"app":"board"}}}'; done
