#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 run.py
ansible-galaxy collection install -r requirements.yml -p collections --offline --force
ANSIBLE_COLLECTIONS_PATH="$PWD/collections" ansible-doc kubernetes.core.k8s --json > collection-doc.json
