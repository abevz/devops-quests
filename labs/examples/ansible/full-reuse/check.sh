#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK_COLLECTION'
import json
manifest=json.load(open('collections/ansible_collections/kubernetes/core/MANIFEST.json'))
assert manifest['collection_info']['version']=='6.1.0'
assert 'kubernetes.core.k8s' in json.load(open('collection-doc.json'))
CHECK_COLLECTION
cd "$(dirname "$0")"
python3 - <<'CHECK'
import json
r=json.load(open("results.json")); assert r and all(c["passed"] for c in r); print(len(r),"full source playbooks passed")
CHECK
