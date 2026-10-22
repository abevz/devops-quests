set -euo pipefail
cd ~/quest
kubectl label deployment blue green release=board --overwrite
kubectl patch deployment blue --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"release":"board","version":"stable"}}}}}'
kubectl patch deployment green --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"release":"board","version":"candidate"}}}}}'
kubectl patch service board --type=merge -p '{"spec":{"selector":{"app":null,"release":"board"}}}'
