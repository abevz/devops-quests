"""On-demand metrics and Gateway controllers in the installation-owned kind."""

import hashlib
import json
import shlex

import yaml

from .components import Components
from .platform import Platform


class BookComponents(Components):
    def namespace(self, run):
        return super().namespace(run).replace("dq-components-", "dq-book-")

    def object(self, run, kind, name, api="v1", namespace=None, **fields):
        metadata = {"name": name, "labels": self.labels(run)}
        if namespace:
            metadata["namespace"] = namespace
        return {"apiVersion": api, "kind": kind, "metadata": metadata, **fields}

    def create(self, run):
        deps = self.r.dependencies(run)
        ns = self.namespace(run)
        self.r.kube(
            "create", "-f", "-", input=json.dumps(self.object(run, "Namespace", ns))
        )
        self.r.kube(
            "label", "namespace", ns, "pod-security.kubernetes.io/enforce=restricted"
        )
        env = {}
        if "metrics" in deps:
            self.metrics(run)
        if "gateway" in deps:
            env.update(self.gateway(run))
        Platform(self.r).put(
            run,
            "book-components.env",
            "\n".join("export " + k + "=" + shlex.quote(v) for k, v in env.items()),
        )

    def metrics(self, run):
        r = self.r
        name = "dq-metrics-" + run["id"]
        ns = self.namespace(run)
        # This API group has one fixed registration name. Never replace an
        # existing server, including an orphan from another bay.
        existing = r.kube(
            "get",
            "apiservice",
            "v1beta1.metrics.k8s.io",
            "--ignore-not-found",
            "-o",
            "name",
        ).stdout.strip()
        if existing:
            raise RuntimeError("Refusing an existing metrics APIService")
        r.load_image("metrics")
        source = list(
            yaml.safe_load_all((r.root / "vendor/metrics-server.yaml").read_text())
        )
        for item in source:
            old = item["metadata"]["name"]
            if old == "system:aggregated-metrics-reader":
                continue  # No aggregate-to-admin/edit/view changes.
            item["metadata"] = {
                "name": "v1beta1.metrics.k8s.io"
                if item["kind"] == "APIService"
                else name,
                "labels": self.labels(run),
            }
            if item["kind"] in {"ServiceAccount", "Deployment", "Service"}:
                item["metadata"]["namespace"] = ns
            if item["kind"] == "RoleBinding":
                item["metadata"]["namespace"] = "kube-system"
            if item["kind"] in {"ClusterRoleBinding", "RoleBinding"}:
                item["metadata"]["name"] = name + (
                    "-auth"
                    if old.endswith("auth-delegator")
                    else "-reader"
                    if item["kind"] == "RoleBinding"
                    else ""
                )
                item["subjects"] = [
                    {"kind": "ServiceAccount", "name": name, "namespace": ns}
                ]
                if old == "system:metrics-server":
                    item["roleRef"]["name"] = name
            if item["kind"] == "Deployment":
                spec = item["spec"]["template"]["spec"]
                spec.pop("priorityClassName", None)
                spec["serviceAccountName"] = name
                spec["securityContext"] = {"fsGroup": 1000}
                c = spec["containers"][0]
                c["image"] = r.images["metrics"]
                c["imagePullPolicy"] = "Never"
                c["args"].append(
                    "--kubelet-insecure-tls"
                )  # Private kind's self-signed kubelet only.
                c["resources"] = {
                    "requests": {"cpu": "50m", "memory": "64Mi"},
                    "limits": {"cpu": "300m", "memory": "256Mi"},
                }
            if item["kind"] == "APIService":
                item["spec"]["service"].update(name=name, namespace=ns)
            r.kube("create", "-f", "-", input=json.dumps(item))
            if item["kind"] == "Service":
                from .book_runtime import metrics_route

                address = r.kube(
                    "-n", ns, "get", "service", name, "-o", "jsonpath={.spec.clusterIP}"
                ).stdout.strip()
                metrics_route(r, run, address)

        r.kube(
            "-n",
            ns,
            "rollout",
            "status",
            "deployment/" + name,
            "--timeout=120s",
            timeout=130,
        )
        r.kube(
            "wait",
            "--for=condition=Available",
            "apiservice/v1beta1.metrics.k8s.io",
            "--timeout=90s",
            timeout=100,
        )

    def gateway(self, run):
        r = self.r
        ns = self.namespace(run)
        target = r.namespace(run)
        name = "dq-gateway-" + run["id"]
        r.load_image("traefik")
        source = (r.root / "vendor/gateway-api.yaml").read_text()
        fingerprint = hashlib.sha256(source.encode()).hexdigest()
        for item in yaml.safe_load_all(source):
            if item["kind"] != "CustomResourceDefinition":
                # The pinned bundle also contains cluster-wide CRD upgrade
                # admission policy. These disposable labs install definitions
                # only and perform no CRD channel/version upgrades.
                if item["kind"] not in {
                    "ValidatingAdmissionPolicy",
                    "ValidatingAdmissionPolicyBinding",
                }:
                    raise RuntimeError("Unsupported Gateway bundle object")
                continue
            metadata = item["metadata"]
            metadata["labels"] = {"devops-quests.installation": r.installation}
            metadata["annotations"] = dict(
                metadata.get("annotations", {}),
                **{"devops-quests.source-sha256": fingerprint},
            )
            existing = r.kube(
                "get", "crd", metadata["name"], "--ignore-not-found", "-o", "json"
            ).stdout.strip()
            if existing:
                if (
                    json.loads(existing)["metadata"]
                    .get("labels", {})
                    .get("devops-quests.installation")
                    != r.installation
                ):
                    raise RuntimeError("Refusing a foreign Gateway API CRD")
                if (
                    json.loads(existing)["metadata"]
                    .get("annotations", {})
                    .get("devops-quests.source-sha256")
                    != fingerprint
                ):
                    raise RuntimeError("Refusing a different Gateway API CRD revision")
            else:
                r.kube("create", "-f", "-", input=json.dumps(item))
            r.kube(
                "wait",
                "--for=condition=Established",
                "crd/" + metadata["name"],
                "--timeout=45s",
            )

        def obj(kind, n, api="v1", namespace=None, **fields):
            return self.object(run, kind, n, api, namespace, **fields)

        rbac = "rbac.authorization.k8s.io/v1"
        verbs = ["get", "list", "watch"]
        rules = [
            {
                "apiGroups": [""],
                "resources": ["services", "secrets", "configmaps"],
                "verbs": verbs,
            },
            {
                "apiGroups": ["discovery.k8s.io"],
                "resources": ["endpointslices"],
                "verbs": verbs,
            },
            {
                "apiGroups": ["gateway.networking.k8s.io"],
                "resources": [
                    "gateways",
                    "httproutes",
                    "grpcroutes",
                    "tlsroutes",
                    "referencegrants",
                    "backendtlspolicies",
                ],
                "verbs": verbs,
            },
            {
                "apiGroups": ["gateway.networking.k8s.io"],
                "resources": [
                    "gateways/status",
                    "httproutes/status",
                    "grpcroutes/status",
                    "backendtlspolicies/status",
                ],
                "verbs": ["update"],
            },
        ]
        crules = [
            {
                "apiGroups": [""],
                "resources": ["namespaces"],
                "verbs": ["list", "watch"],
            },
            {
                "apiGroups": ["gateway.networking.k8s.io"],
                "resources": ["gatewayclasses"],
                "verbs": verbs,
            },
            {
                "apiGroups": ["gateway.networking.k8s.io"],
                "resources": ["gatewayclasses/status"],
                "resourceNames": [name],
                "verbs": ["update"],
            },
        ]
        subject = [{"kind": "ServiceAccount", "name": "gateway", "namespace": ns}]
        objects = [
            obj("ServiceAccount", "gateway", namespace=ns),
            obj("Role", name, rbac, target, rules=rules),
            obj(
                "RoleBinding",
                name,
                rbac,
                target,
                roleRef={
                    "apiGroup": "rbac.authorization.k8s.io",
                    "kind": "Role",
                    "name": name,
                },
                subjects=subject,
            ),
            obj("ClusterRole", name, rbac, rules=crules),
            obj(
                "ClusterRoleBinding",
                name,
                rbac,
                roleRef={
                    "apiGroup": "rbac.authorization.k8s.io",
                    "kind": "ClusterRole",
                    "name": name,
                },
                subjects=subject,
            ),
            obj(
                "GatewayClass",
                name,
                "gateway.networking.k8s.io/v1",
                spec={"controllerName": "traefik.io/gateway-controller"},
            ),
            obj(
                "Service",
                "gateway",
                namespace=ns,
                spec={
                    "selector": {"app": "gateway"},
                    "ports": [{"port": 8000, "targetPort": 8000}],
                },
            ),
            obj(
                "Deployment",
                "gateway",
                "apps/v1",
                ns,
                spec={
                    "replicas": 1,
                    "selector": {"matchLabels": {"app": "gateway"}},
                    "template": {
                        "metadata": {"labels": {"app": "gateway"}},
                        "spec": {
                            "serviceAccountName": "gateway",
                            "securityContext": {
                                "runAsNonRoot": True,
                                "runAsUser": 65532,
                                "seccompProfile": {"type": "RuntimeDefault"},
                            },
                            "containers": [
                                {
                                    "name": "gateway",
                                    "image": r.images["traefik"],
                                    "imagePullPolicy": "Never",
                                    "command": ["traefik"],
                                    "args": [
                                        "--entrypoints.web.address=:8000",
                                        "--providers.kubernetesgateway",
                                        "--providers.kubernetesgateway.namespaces="
                                        + target,
                                        "--providers.kubernetesgateway.labelselector=devops-quests.run="
                                        + run["id"],
                                        "--log.level=ERROR",
                                    ],
                                    "resources": {
                                        "requests": {"cpu": "20m", "memory": "32Mi"},
                                        "limits": {"cpu": "300m", "memory": "128Mi"},
                                    },
                                    "securityContext": {
                                        "allowPrivilegeEscalation": False,
                                        "capabilities": {"drop": ["ALL"]},
                                        "readOnlyRootFilesystem": True,
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
            ),
        ]
        for item in objects:
            r.kube("create", "-f", "-", input=json.dumps(item))
        r.kube(
            "-n",
            ns,
            "rollout",
            "status",
            "deployment/gateway",
            "--timeout=90s",
            timeout=100,
        )
        return {
            "GATEWAY_CLASS": name,
            "GATEWAY_URL": "http://gateway." + ns + ".svc:8000",
        }

    def teardown(self, run):
        deps = self.r.dependencies(run)
        targets = []
        if "metrics" in deps:
            name = "dq-metrics-" + run["id"]
            targets += [
                ("apiservice", "v1beta1.metrics.k8s.io", None),
                ("clusterrolebinding", name + "-auth", None),
                ("clusterrolebinding", name, None),
                ("clusterrole", name, None),
                ("rolebinding", name + "-reader", "kube-system"),
            ]
        if "gateway" in deps:
            name = "dq-gateway-" + run["id"]
            targets += [
                (kind, name, None)
                for kind in ("gatewayclass", "clusterrolebinding", "clusterrole")
            ]
        targets.append(("namespace", self.namespace(run), None))
        found = []
        for kind, name, ns in targets:
            args = ("-n", ns) if ns else ()
            raw = self.r.kube(
                *args, "get", kind, name, "--ignore-not-found", "-o", "json"
            ).stdout.strip()
            if raw:
                labels = json.loads(raw)["metadata"].get("labels", {})
                if any(labels.get(k) != v for k, v in self.labels(run).items()):
                    raise RuntimeError("Refusing a foreign book component")
                found.append((kind, name, args))
        if "metrics" in deps:
            from .book_runtime import remove_metrics_route

            remove_metrics_route(self.r, run)
        for kind, name, args in found:
            if kind == "namespace":
                self.r.remove_namespace(name)
            else:
                self.r.kube(*args, "delete", kind, name)
