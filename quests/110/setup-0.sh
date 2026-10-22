set -euo pipefail
cd ~/quest
cat > board.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "board"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "board"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "runAsGroup": 1000,
          "fsGroup": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-110\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "8Mi"
              },
              "limits": {
                "cpu": "200m",
                "memory": "32Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            }
          }
        ]
      }
    }
  }
}
DQ_ASSET
python3 - board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.json
cat > service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "selector": {
      "app": "board"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": 8080
      }
    ]
  }
}
DQ_ASSET
python3 - service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.json
kubectl rollout status deployment/board --timeout=60s
source components.env
cat > dns-config.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "station-dns"
  },
  "data": {
    "Corefile": ".:1053 {\n errors\n hosts {\n  127.0.0.1 station.internal\n  ttl 1\n }\n}\n"
  }
}
DQ_ASSET
python3 - dns-config.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f dns-config.json
cat > dns.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "station-dns"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "station-dns"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "station-dns"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "runAsGroup": 1000,
          "fsGroup": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "__COREDNS_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "/coredns",
              "-conf",
              "/etc/station/Corefile"
            ],
            "resources": {
              "requests": {
                "cpu": "20m",
                "memory": "16Mi"
              },
              "limits": {
                "cpu": "200m",
                "memory": "64Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ],
                "add": [
                  "NET_BIND_SERVICE"
                ]
              }
            },
            "volumeMounts": [
              {
                "name": "corefile",
                "mountPath": "/etc/station",
                "readOnly": true
              }
            ],
            "readinessProbe": {
              "tcpSocket": {
                "port": 1053
              },
              "periodSeconds": 1
            }
          }
        ],
        "volumes": [
          {
            "name": "corefile",
            "configMap": {
              "name": "station-dns"
            }
          }
        ],
        "terminationGracePeriodSeconds": 1
      }
    }
  }
}
DQ_ASSET
python3 - dns.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'DNS_IMAGE'
import os
from pathlib import Path
p=Path('dns.json');p.write_text(p.read_text().replace('__COREDNS_IMAGE__',os.environ['COREDNS_IMAGE']))
DNS_IMAGE
kubectl apply -f dns.json
cat > dns-service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "station-dns"
  },
  "spec": {
    "selector": {
      "app": "station-dns"
    },
    "ports": [
      {
        "name": "dns-udp",
        "port": 53,
        "targetPort": 1053,
        "protocol": "UDP"
      },
      {
        "name": "dns-tcp",
        "port": 53,
        "targetPort": 1053,
        "protocol": "TCP"
      }
    ]
  }
}
DQ_ASSET
python3 - dns-service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f dns-service.json
cat > client.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "client"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "client"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "client"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "runAsGroup": 1000,
          "fsGroup": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sleep",
              "3600"
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "8Mi"
              },
              "limits": {
                "cpu": "200m",
                "memory": "32Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            }
          }
        ],
        "dnsPolicy": "None",
        "dnsConfig": {
          "nameservers": [
            "__DNS_IP__"
          ]
        }
      }
    }
  }
}
DQ_ASSET
python3 - client.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}')
export DNS_IP="$dns_ip"
python3 - <<'DNS_CLIENT'
import os
from pathlib import Path
p=Path('client.json');p.write_text(p.read_text().replace('__DNS_IP__',os.environ['DNS_IP']))
DNS_CLIENT
kubectl apply -f client.json
kubectl rollout status deployment/station-dns --timeout=60s
kubectl rollout status deployment/client --timeout=60s
printf '%s\n' "$INGRESS_IP" > expected-dns-address
source components.env
cat > ingress.json <<'DQ_ASSET'
{
  "apiVersion": "networking.k8s.io/v1",
  "kind": "Ingress",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "ingressClassName": "__CLASS__",
    "rules": [
      {
        "host": "station.internal",
        "http": {
          "paths": [
            {
              "path": "/",
              "pathType": "Prefix",
              "backend": {
                "service": {
                  "name": "board",
                  "port": {
                    "number": 8099
                  }
                }
              }
            }
          ]
        }
      }
    ]
  }
}
DQ_ASSET
python3 - ingress.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'INGRESS_CLASS'
import os
from pathlib import Path
p=Path('ingress.json');p.write_text(p.read_text().replace('__CLASS__',os.environ['INGRESS_CLASS']))
INGRESS_CLASS
kubectl apply -f ingress.json
jq -n --arg url "$INGRESS_URL" --arg class "$INGRESS_CLASS" '{url:$url,class:$class}' > ingress-target.json
