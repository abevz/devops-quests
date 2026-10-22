"""A real, bounded Prometheus with one static target in the active bay."""

import json

from .components import Components
from .platform import Platform


class Prometheus(Components):
    def namespace(self, run):
        return super().namespace(run).replace("dq-components-", "dq-observe-")

    def create(self, run):
        r = self.r
        ns = self.namespace(run)
        r.load_image("prometheus")
        labels = self.labels(run)
        config = {
            "global": {
                "scrape_interval": "2s",
                "scrape_timeout": "1s",
                "evaluation_interval": "2s",
            },
            "scrape_configs": [
                {
                    "job_name": "board",
                    "metrics_path": "/metrics.txt",
                    "static_configs": [
                        {"targets": ["board." + r.namespace(run) + ".svc:8080"]}
                    ],
                }
            ],
        }
        import yaml

        objects = [
            {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {
                    "name": ns,
                    "labels": dict(
                        labels, **{"pod-security.kubernetes.io/enforce": "restricted"}
                    ),
                },
            },
            {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {"name": "scrape", "namespace": ns, "labels": labels},
                "data": {"prometheus.yml": yaml.safe_dump(config)},
            },
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {"name": "prometheus", "namespace": ns, "labels": labels},
                "spec": {
                    "selector": {"app": "prometheus"},
                    "ports": [{"port": 9090, "targetPort": 9090}],
                },
            },
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {"name": "prometheus", "namespace": ns, "labels": labels},
                "spec": {
                    "replicas": 1,
                    "selector": {"matchLabels": {"app": "prometheus"}},
                    "template": {
                        "metadata": {"labels": {"app": "prometheus"}},
                        "spec": {
                            "automountServiceAccountToken": False,
                            "terminationGracePeriodSeconds": 1,
                            "securityContext": {
                                "runAsNonRoot": True,
                                "runAsUser": 65534,
                                "fsGroup": 65534,
                                "seccompProfile": {"type": "RuntimeDefault"},
                            },
                            "volumes": [
                                {"name": "config", "configMap": {"name": "scrape"}},
                                {"name": "data", "emptyDir": {"sizeLimit": "64Mi"}},
                            ],
                            "containers": [
                                {
                                    "name": "prometheus",
                                    "image": r.images["prometheus"],
                                    "imagePullPolicy": "Never",
                                    "command": ["/bin/prometheus"],
                                    "args": [
                                        "--config.file=/etc/prometheus/prometheus.yml",
                                        "--storage.tsdb.path=/prometheus",
                                        "--storage.tsdb.retention.time=10m",
                                        "--storage.tsdb.retention.size=32MB",
                                        "--web.listen-address=:9090",
                                    ],
                                    "securityContext": {
                                        "allowPrivilegeEscalation": False,
                                        "readOnlyRootFilesystem": True,
                                        "capabilities": {"drop": ["ALL"]},
                                    },
                                    "resources": {
                                        "requests": {"cpu": "20m", "memory": "32Mi"},
                                        "limits": {"cpu": "300m", "memory": "256Mi"},
                                    },
                                    "volumeMounts": [
                                        {
                                            "name": "config",
                                            "mountPath": "/etc/prometheus",
                                            "readOnly": True,
                                        },
                                        {"name": "data", "mountPath": "/prometheus"},
                                    ],
                                    "readinessProbe": {
                                        "httpGet": {"path": "/-/ready", "port": 9090},
                                        "periodSeconds": 1,
                                    },
                                }
                            ],
                        },
                    },
                },
            },
        ]
        for item in objects:
            r.kube("create", "-f", "-", input=json.dumps(item))
        r.kube(
            "-n",
            ns,
            "rollout",
            "status",
            "deployment/prometheus",
            "--timeout=90s",
            timeout=100,
        )
        Platform(r).put(
            run,
            "prometheus-target.json",
            json.dumps(
                {"url": "http://prometheus." + ns + ".svc:9090", "job": "board"}
            ),
        )

    def teardown(self, run):
        ns = self.namespace(run)
        raw = self.r.kube(
            "get", "namespace", ns, "--ignore-not-found", "-o", "json"
        ).stdout.strip()
        if raw:
            if any(
                json.loads(raw)["metadata"].get("labels", {}).get(k) != v
                for k, v in self.labels(run).items()
            ):
                raise RuntimeError("Refusing a foreign Prometheus namespace")
            self.r.remove_namespace(ns)
