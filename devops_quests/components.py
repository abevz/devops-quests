"""Pinned, on-demand controllers scoped to one disposable training bay."""

import json
import re
import shlex

from .platform import Platform


class Components:
    def __init__(self, runtime):
        self.r = runtime

    def namespace(self, run):
        if not re.fullmatch(r"[a-f0-9]{24}", run["id"]):
            raise ValueError("Invalid component bay identity")
        return "dq-components-" + run["id"]

    def labels(self, run):
        return {
            "devops-quests.installation": self.r.installation,
            "devops-quests.run": run["id"],
        }

    def create(self, run):
        self.namespace(run)
        deps = self.r.dependencies(run)
        env = {}
        if "dns" in deps:
            self.r.load_image("coredns")
            env["COREDNS_IMAGE"] = self.r.images["coredns"]
        if "ingress" in deps:
            self.r.load_image("traefik")
            env.update(self.ingress(run))
        Platform(self.r).put(
            run,
            "components.env",
            "\n".join(
                "export " + key + "=" + shlex.quote(value) for key, value in env.items()
            ),
        )

    def ingress(self, run):
        namespace = self.namespace(run)
        target = self.r.namespace(run)
        name = "dq-ingress-" + run["id"]
        labels = self.labels(run)

        def obj(kind, name, **fields):
            api = (
                "v1"
                if kind in {"Namespace", "Service", "ServiceAccount"}
                else "rbac.authorization.k8s.io/v1"
            )
            return {
                "apiVersion": api,
                "kind": kind,
                "metadata": {"name": name, "labels": labels},
                **fields,
            }

        objects = [
            obj("Namespace", namespace),
            obj("ServiceAccount", "ingress"),
            obj(
                "Role",
                name,
                rules=[
                    {
                        "apiGroups": [""],
                        "resources": ["services", "secrets"],
                        "verbs": ["get", "list", "watch"],
                    },
                    {
                        "apiGroups": ["discovery.k8s.io"],
                        "resources": ["endpointslices"],
                        "verbs": ["get", "list", "watch"],
                    },
                    {
                        "apiGroups": ["networking.k8s.io"],
                        "resources": ["ingresses"],
                        "verbs": ["get", "list", "watch"],
                    },
                    {
                        "apiGroups": ["networking.k8s.io"],
                        "resources": ["ingresses/status"],
                        "verbs": ["update"],
                    },
                ],
            ),
            obj(
                "RoleBinding",
                name,
                roleRef={
                    "apiGroup": "rbac.authorization.k8s.io",
                    "kind": "Role",
                    "name": name,
                },
                subjects=[
                    {
                        "kind": "ServiceAccount",
                        "name": "ingress",
                        "namespace": namespace,
                    }
                ],
            ),
            obj(
                "ClusterRole",
                name,
                rules=[
                    {
                        "apiGroups": ["networking.k8s.io"],
                        "resources": ["ingressclasses"],
                        "verbs": ["get", "list", "watch"],
                    },
                    {
                        "apiGroups": [""],
                        "resources": ["nodes"],
                        "verbs": ["get", "list", "watch"],
                    },
                ],
            ),
            obj(
                "ClusterRoleBinding",
                name,
                roleRef={
                    "apiGroup": "rbac.authorization.k8s.io",
                    "kind": "ClusterRole",
                    "name": name,
                },
                subjects=[
                    {
                        "kind": "ServiceAccount",
                        "name": "ingress",
                        "namespace": namespace,
                    }
                ],
            ),
            {
                "apiVersion": "networking.k8s.io/v1",
                "kind": "IngressClass",
                "metadata": {"name": name, "labels": labels},
                "spec": {"controller": "traefik.io/ingress-controller"},
            },
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {"name": "ingress", "labels": labels},
                "spec": {
                    "replicas": 1,
                    "selector": {"matchLabels": {"app": "ingress"}},
                    "template": {
                        "metadata": {"labels": {"app": "ingress"}},
                        "spec": {
                            "serviceAccountName": "ingress",
                            "securityContext": {
                                "runAsNonRoot": True,
                                "runAsUser": 65532,
                                "seccompProfile": {"type": "RuntimeDefault"},
                            },
                            "containers": [
                                {
                                    "name": "traefik",
                                    "image": self.r.images["traefik"],
                                    "imagePullPolicy": "Never",
                                    "command": ["traefik"],
                                    "args": [
                                        "--entrypoints.web.address=:8000",
                                        "--providers.kubernetesingress",
                                        "--providers.kubernetesingress.namespaces="
                                        + target,
                                        "--providers.kubernetesingress.ingressclass="
                                        + name,
                                        "--log.level=ERROR",
                                    ],
                                    "securityContext": {
                                        "allowPrivilegeEscalation": False,
                                        "capabilities": {"drop": ["ALL"]},
                                        "readOnlyRootFilesystem": True,
                                    },
                                    "resources": {
                                        "requests": {"cpu": "20m", "memory": "32Mi"},
                                        "limits": {"cpu": "300m", "memory": "128Mi"},
                                    },
                                    "readinessProbe": {
                                        "tcpSocket": {"port": 8000},
                                        "periodSeconds": 1,
                                    },
                                }
                            ],
                        },
                    },
                },
            },
            obj(
                "Service",
                "ingress",
                spec={
                    "selector": {"app": "ingress"},
                    "ports": [{"port": 8000, "targetPort": 8000}],
                },
            ),
        ]
        objects[0]["metadata"]["labels"] = dict(
            labels, **{"pod-security.kubernetes.io/enforce": "restricted"}
        )
        for item in objects:
            if item["kind"] in {"Role", "RoleBinding"}:
                item["metadata"]["namespace"] = target
            elif item["kind"] in {"ServiceAccount", "Deployment", "Service"}:
                item["metadata"]["namespace"] = namespace
            self.r.kube("create", "-f", "-", input=json.dumps(item))
        self.r.kube(
            "-n",
            namespace,
            "rollout",
            "status",
            "deployment/ingress",
            "--timeout=90s",
            timeout=100,
        )
        return {
            "INGRESS_CLASS": name,
            "INGRESS_URL": "http://ingress." + namespace + ".svc:8000",
            "INGRESS_IP": self.r.kube(
                "-n",
                namespace,
                "get",
                "service",
                "ingress",
                "-o",
                "jsonpath={.spec.clusterIP}",
            ).stdout.strip(),
        }

    def teardown(self, run):
        self.namespace(run)
        if "ingress" not in self.r.dependencies(run):
            return
        name = "dq-ingress-" + run["id"]
        found = []
        targets = [
            (kind, name)
            for kind in ("clusterrolebinding", "clusterrole", "ingressclass")
        ]
        targets.append(("namespace", self.namespace(run)))
        for kind, resource in targets:
            result = self.r.kube(
                "get", kind, resource, "--ignore-not-found", "-o", "json"
            )
            if result.stdout.strip():
                item = json.loads(result.stdout)
                labels = item.get("metadata", {}).get("labels", {})
                if any(
                    labels.get(key) != value for key, value in self.labels(run).items()
                ):
                    raise RuntimeError("Refusing a foreign component resource")
                found.append((kind, resource))
        for kind, resource in found:
            if kind == "namespace":
                self.r.remove_namespace(resource)
            else:
                self.r.kube("delete", kind, resource)
