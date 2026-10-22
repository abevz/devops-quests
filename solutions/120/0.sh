set -euo pipefail
cd ~/quest
kubectl patch service shelf --type=json -p '[{"op": "replace", "path": "/spec/selector", "value": {"app": "shelf"}}]'
cat > egress.json <<'DQ_ASSET'
{
  "apiVersion": "networking.k8s.io/v1",
  "kind": "NetworkPolicy",
  "metadata": {
    "name": "client-egress"
  },
  "spec": {
    "podSelector": {
      "matchLabels": {
        "app": "client"
      }
    },
    "policyTypes": [
      "Egress"
    ],
    "egress": [
      {
        "to": [
          {
            "namespaceSelector": {
              "matchLabels": {
                "kubernetes.io/metadata.name": "kube-system"
              }
            },
            "podSelector": {
              "matchLabels": {
                "k8s-app": "kube-dns"
              }
            }
          }
        ],
        "ports": [
          {
            "port": 53,
            "protocol": "UDP"
          },
          {
            "port": 53,
            "protocol": "TCP"
          }
        ]
      },
      {
        "to": [
          {
            "podSelector": {
              "matchLabels": {
                "app": "shelf"
              }
            }
          }
        ],
        "ports": [
          {
            "port": 8080,
            "protocol": "TCP"
          }
        ]
      }
    ]
  }
}
DQ_ASSET
python3 - egress.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f egress.json
