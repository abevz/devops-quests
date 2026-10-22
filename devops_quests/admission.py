"""Private, bounded TLS admission service; never a host or cluster-wide policy."""

import base64
import json
import os
import shutil
import time

from .components import Components
from .platform import Platform


class Admission(Components):
    def name(self, run):
        self.namespace(run)
        return "dq-webhook-" + run["id"]

    def create(self, run):
        r = self.r
        uid, gid = os.getuid(), os.getgid()
        if uid == 0:
            raise RuntimeError(
                "The training admission backend must run as a non-root account"
            )
        name = self.name(run)
        folder = r.state / "bays" / run["id"] / "webhook"
        folder.mkdir(mode=0o700)
        shutil.copyfile(
            r.root / "devops_quests/admission_server.py", folder / "server.py"
        )
        r.command(
            (
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=" + name,
                "-addext",
                "subjectAltName=DNS:" + name,
                "-keyout",
                str(folder / "key.pem"),
                "-out",
                str(folder / "cert.pem"),
            ),
            timeout=20,
        )
        (folder / "key.pem").chmod(0o400)
        r.docker(
            "run",
            "-d",
            "--name",
            name,
            *r.labels(),
            "--label",
            "devops-quests.run=" + run["id"],
            "--network",
            r.network,
            "--network-alias",
            name,
            "--user",
            f"{uid}:{gid}",
            "--read-only",
            "--cap-drop",
            "ALL",
            "--security-opt",
            "no-new-privileges",
            "--pids-limit",
            "32",
            "--memory",
            "64m",
            "--memory-swap",
            "64m",
            "--cpus",
            "0.25",
            "--mount",
            "type=bind,src=" + str(folder) + ",dst=/webhook,readonly",
            "--env",
            "TRAINING_NAMESPACE=" + r.namespace(run),
            "--entrypoint",
            "python3",
            r.image,
            "-B",
            "/webhook/server.py",
        )
        cert = (folder / "cert.pem").read_text()
        Platform(r).put(run, "admission-ca.pem", cert)
        Platform(r).put(
            run,
            "admission-target.json",
            json.dumps(
                {
                    "url": "https://" + name + ":8443/validate",
                    "namespace": r.namespace(run),
                }
            ),
        )
        for _ in range(30):
            if (
                r.exec(
                    run,
                    "curl -fsS --max-time 2 --cacert ~/quest/admission-ca.pem https://"
                    + name
                    + ":8443/ready",
                    check=False,
                ).returncode
                == 0
            ):
                break
            time.sleep(1)
        else:
            raise RuntimeError("Training admission server did not become ready")
        item = {
            "apiVersion": "admissionregistration.k8s.io/v1",
            "kind": "ValidatingWebhookConfiguration",
            "metadata": {"name": name, "labels": self.labels(run)},
            "webhooks": [
                {
                    "name": "route.training.devops-quests.local",
                    "admissionReviewVersions": ["v1"],
                    "sideEffects": "None",
                    "failurePolicy": "Fail",
                    "timeoutSeconds": 2,
                    "namespaceSelector": {"matchLabels": self.labels(run)},
                    "matchPolicy": "Exact",
                    "matchConditions": [
                        {"name": "only-route", "expression": "request.name == 'route'"}
                    ],
                    "rules": [
                        {
                            "operations": ["CREATE", "UPDATE"],
                            "apiGroups": [""],
                            "apiVersions": ["v1"],
                            "resources": ["configmaps"],
                            "scope": "Namespaced",
                        }
                    ],
                    "clientConfig": {
                        "url": "https://" + name + ":8443/retired",
                        "caBundle": base64.b64encode(cert.encode()).decode(),
                    },
                }
            ],
        }
        r.kube("create", "-f", "-", input=json.dumps(item))
        identity = {
            "uid": json.loads(
                r.kube(
                    "get", "validatingwebhookconfiguration", name, "-o", "json"
                ).stdout
            )["metadata"]["uid"],
            "container": r.inspect(name)["Id"],
            "webhook": item["webhooks"][0],
        }
        (r.state / "bays" / run["id"] / "webhook-identity.json").write_text(
            json.dumps(identity)
        )
        Platform(r).put(run, "webhook-repair.json", json.dumps({"action": "inspect"}))
        rbac = "rbac.authorization.k8s.io/v1"
        grant = {
            "apiVersion": rbac,
            "kind": "ClusterRole",
            "metadata": {"name": name, "labels": self.labels(run)},
            "rules": [
                {
                    "apiGroups": ["admissionregistration.k8s.io"],
                    "resources": ["validatingwebhookconfigurations"],
                    "resourceNames": [name],
                    "verbs": ["get"],
                }
            ],
        }
        binding = {
            "apiVersion": rbac,
            "kind": "ClusterRoleBinding",
            "metadata": {"name": name, "labels": self.labels(run)},
            "roleRef": {
                "apiGroup": "rbac.authorization.k8s.io",
                "kind": "ClusterRole",
                "name": name,
            },
            "subjects": [
                {
                    "kind": "ServiceAccount",
                    "name": "player",
                    "namespace": r.namespace(run),
                }
            ],
        }
        for value in (grant, binding):
            r.kube("create", "-f", "-", input=json.dumps(value))

    def teardown(self, run):
        name = self.name(run)
        raw = self.r.kube(
            "get",
            "validatingwebhookconfiguration",
            name,
            "--ignore-not-found",
            "-o",
            "json",
        ).stdout.strip()
        container = self.r.inspect(name)
        if raw and any(
            json.loads(raw)["metadata"].get("labels", {}).get(k) != v
            for k, v in self.labels(run).items()
        ):
            raise RuntimeError("Refusing a foreign admission configuration")
        if container and (
            container["Config"].get("Labels", {}).get("devops-quests.run") != run["id"]
            or not self.r.owned(name)
        ):
            raise RuntimeError("Refusing a foreign admission container")
        grants = []
        for kind in ("clusterrolebinding", "clusterrole"):
            text = self.r.kube(
                "get", kind, name, "--ignore-not-found", "-o", "json"
            ).stdout.strip()
            if text:
                if any(
                    json.loads(text)["metadata"].get("labels", {}).get(k) != v
                    for k, v in self.labels(run).items()
                ):
                    raise RuntimeError("Refusing a foreign admission read grant")
                grants.append(kind)
        if raw:
            self.r.kube("delete", "validatingwebhookconfiguration", name)
        for kind in grants:
            self.r.kube("delete", kind, name)
        if container:
            self.r.remove_container(name)

    def control(self, run):
        from .sandbox_evidence import CONTROL_READER

        r = self.r
        name = self.name(run)
        result = r.exec(
            run,
            "python3 - webhook-repair.json <<'WEBHOOK_CONTROL'\n"
            + CONTROL_READER
            + "\nWEBHOOK_CONTROL\n",
            check=False,
            timeout=3,
        )
        if result.returncode:
            return
        try:
            request = json.loads(result.stdout)
        except ValueError:
            return
        if request != {"action": "restore-path"}:
            return
        identity = json.loads(
            (r.state / "bays" / run["id"] / "webhook-identity.json").read_text()
        )
        container = r.inspect(name)
        if (
            not container
            or container["Id"] != identity["container"]
            or container["Image"] != r.image
            or not r.owned(name)
            or container["Config"].get("Labels", {}).get("devops-quests.run")
            != run["id"]
            or r.network not in container["NetworkSettings"]["Networks"]
        ):
            raise RuntimeError("Refusing a replaced admission server")
        config = json.loads(
            r.kube("get", "validatingwebhookconfiguration", name, "-o", "json").stdout
        )
        wanted = identity["webhook"]
        actual = config.get("webhooks", [])
        if config["metadata"]["uid"] != identity["uid"] or len(actual) != 1:
            raise RuntimeError("Refusing a replaced admission configuration")
        for field in (
            "name",
            "rules",
            "namespaceSelector",
            "failurePolicy",
            "sideEffects",
            "timeoutSeconds",
            "admissionReviewVersions",
            "matchPolicy",
            "matchConditions",
        ):
            if actual[0].get(field) != wanted[field]:
                raise RuntimeError("Refusing a changed admission scope")
        client = actual[0].get("clientConfig", {})
        if (
            client.get("caBundle") != wanted["clientConfig"]["caBundle"]
            or client.get("service")
            or client.get("url")
            not in {
                "https://" + name + ":8443/retired",
                "https://" + name + ":8443/validate",
            }
        ):
            raise RuntimeError("Refusing a changed admission endpoint")
        if client["url"].endswith("/retired"):
            r.kube(
                "patch",
                "validatingwebhookconfiguration",
                name,
                "--type=json",
                "-p",
                json.dumps(
                    [
                        {
                            "op": "test",
                            "path": "/metadata/uid",
                            "value": identity["uid"],
                        },
                        {
                            "op": "test",
                            "path": "/webhooks/0/clientConfig/url",
                            "value": client["url"],
                        },
                        {
                            "op": "replace",
                            "path": "/webhooks/0/clientConfig/url",
                            "value": "https://" + name + ":8443/validate",
                        },
                    ]
                ),
            )
