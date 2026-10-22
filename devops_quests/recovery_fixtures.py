"""Run-scoped storage and finalizer fixtures inside the disposable kind only."""

import hashlib
import json

from .components import Components
from .owned_kind import owned_node
from .platform import Platform

FINALIZER = "training.devops-quests.local/cleanup"


class RecoveryFixtures(Components):
    def path(self, run):
        self.namespace(run)
        return self.r.state / "bays" / run["id"] / "recovery-fixture.json"

    def save(self, run, value):
        path = self.path(run)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(value))
        temporary.chmod(0o600)
        temporary.replace(path)

    def create(self, run):
        self.namespace(run)
        if run["level"] == 124:
            self.storage(run)
        elif run["level"] == 129:
            self.finalizer(run)

    def storage(self, run):
        r = self.r
        name = "dq-record-" + run["id"]
        node = owned_node(r, run)
        directory = "/var/local/dq-" + r.installation + "/" + run["id"]
        r.docker(
            "exec",
            node,
            "sh",
            "-c",
            f'set -eu; install -d -m 0770 -o 1000 -g 1000 -- {directory}; printf "north-124\\n" > {directory}/index.html; chown 1000:1000 {directory}/index.html; chmod 0640 {directory}/index.html',
        )
        data = {
            "level": 124,
            "name": name,
            "directory": directory,
            "pv_uid": None,
            "installation": r.installation,
            "run": run["id"],
        }
        self.save(run, data)
        sc = {
            "apiVersion": "storage.k8s.io/v1",
            "kind": "StorageClass",
            "metadata": {"name": name, "labels": self.labels(run)},
            "provisioner": "kubernetes.io/no-provisioner",
            "volumeBindingMode": "WaitForFirstConsumer",
            "reclaimPolicy": "Delete",
        }
        pv = {
            "apiVersion": "v1",
            "kind": "PersistentVolume",
            "metadata": {"name": name, "labels": self.labels(run)},
            "spec": {
                "capacity": {"storage": "16Mi"},
                "volumeMode": "Filesystem",
                "accessModes": ["ReadWriteOnce"],
                "persistentVolumeReclaimPolicy": "Delete",
                "storageClassName": name,
                "local": {"path": directory},
                "nodeAffinity": {
                    "required": {
                        "nodeSelectorTerms": [
                            {
                                "matchExpressions": [
                                    {
                                        "key": "kubernetes.io/hostname",
                                        "operator": "In",
                                        "values": [node],
                                    }
                                ]
                            }
                        ]
                    }
                },
            },
        }
        for item in (sc, pv):
            r.kube("create", "-f", "-", input=json.dumps(item))
        data["pv_uid"] = json.loads(r.kube("get", "pv", name, "-o", "json").stdout)[
            "metadata"
        ]["uid"]
        self.save(run, data)
        rbac = "rbac.authorization.k8s.io/v1"
        role = {
            "apiVersion": rbac,
            "kind": "ClusterRole",
            "metadata": {"name": name, "labels": self.labels(run)},
            "rules": [
                {
                    "apiGroups": [""],
                    "resources": ["persistentvolumes"],
                    "resourceNames": [name],
                    "verbs": ["get", "patch"],
                },
                {
                    "apiGroups": ["storage.k8s.io"],
                    "resources": ["storageclasses"],
                    "resourceNames": [name],
                    "verbs": ["get"],
                },
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
        for item in (role, binding):
            r.kube("create", "-f", "-", input=json.dumps(item))
        Platform(r).put(
            run,
            "volume-contract.json",
            json.dumps(
                {"volume": name, "storageClass": name, "pv_uid": data["pv_uid"]}
            ),
        )

    def finalizer(self, run):
        r = self.r
        ns = r.namespace(run)
        labels = self.labels(run)
        parent = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
                "name": "station",
                "namespace": ns,
                "labels": labels,
                "finalizers": [FINALIZER],
            },
            "data": {"record": "synthetic-129"},
        }
        r.kube("create", "-f", "-", input=json.dumps(parent))
        parent = json.loads(
            r.kube("-n", ns, "get", "configmap", "station", "-o", "json").stdout
        )
        data = {
            "level": 129,
            "installation": r.installation,
            "run": run["id"],
            "parent_uid": parent["metadata"]["uid"],
            "child_uid": None,
            "control_uid": None,
        }
        self.save(run, data)
        for name, value in (
            ("station-record", "synthetic-associated"),
            ("control", "keep-129"),
        ):
            item = {
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {
                    "name": name,
                    "namespace": ns,
                    "labels": dict(
                        labels,
                        **(
                            {
                                "training.devops-quests.local/parent-uid": data[
                                    "parent_uid"
                                ]
                            }
                            if name == "station-record"
                            else {}
                        ),
                    ),
                },
                "stringData": {"value": value},
            }
            r.kube("create", "-f", "-", input=json.dumps(item))
            item = json.loads(
                r.kube("-n", ns, "get", "secret", name, "-o", "json").stdout
            )
            data["child_uid" if name == "station-record" else "control_uid"] = item[
                "metadata"
            ]["uid"]
            if name == "control":
                data["control_hash"] = hashlib.sha256(
                    json.dumps(item["data"], sort_keys=True).encode()
                ).hexdigest()
            self.save(run, data)
        Platform(r).put(
            run,
            "cleanup-contract.json",
            json.dumps(
                {
                    k: v
                    for k, v in data.items()
                    if k not in {"installation", "run", "level"}
                }
            ),
        )

    def identity(self, run):
        path = self.path(run)
        if not path.exists():
            return None
        data = json.loads(path.read_text())
        if (
            data.get("installation") != self.r.installation
            or data.get("run") != run["id"]
            or data.get("level") != run["level"]
        ):
            raise RuntimeError("Refusing a foreign recovery fixture")
        return data

    def raw_delete(self, run, kind, name, uid):
        ns = self.r.namespace(run)
        url = "/api/v1/namespaces/" + ns + "/" + kind + "/" + name
        self.r.kube(
            "delete",
            "--raw=" + url,
            "-f",
            "-",
            input=json.dumps(
                {
                    "apiVersion": "v1",
                    "kind": "DeleteOptions",
                    "preconditions": {"uid": uid},
                }
            ),
        )

    def before_namespace(self, run):
        if run["level"] != 129:
            return
        data = self.identity(run)
        if not data:
            return
        r = self.r
        ns = r.namespace(run)
        resources = {}
        for kind, name, key in (
            ("secret", "station-record", "child_uid"),
            ("configmap", "station", "parent_uid"),
        ):
            text = r.kube(
                "-n", ns, "get", kind, name, "--ignore-not-found", "-o", "json"
            ).stdout.strip()
            if text:
                item = json.loads(text)
                if item["metadata"]["uid"] != data[key] or any(
                    item["metadata"].get("labels", {}).get(k) != v
                    for k, v in self.labels(run).items()
                ):
                    raise RuntimeError("Refusing a replaced finalizer fixture")
                resources[kind] = item
        if "configmap" in resources:
            parent = resources["configmap"]
            finalizers = parent["metadata"].get("finalizers", [])
            if finalizers not in ([], [FINALIZER]):
                raise RuntimeError("Refusing an unknown finalizer")
        if "secret" in resources:
            self.raw_delete(run, "secrets", "station-record", data["child_uid"])
        if "configmap" in resources:
            if not parent["metadata"].get("deletionTimestamp"):
                self.raw_delete(run, "configmaps", "station", data["parent_uid"])
            if finalizers:
                r.kube(
                    "-n",
                    ns,
                    "patch",
                    "configmap",
                    "station",
                    "--type=json",
                    "-p",
                    json.dumps(
                        [
                            {
                                "op": "test",
                                "path": "/metadata/uid",
                                "value": data["parent_uid"],
                            },
                            {
                                "op": "test",
                                "path": "/metadata/finalizers",
                                "value": [FINALIZER],
                            },
                            {"op": "remove", "path": "/metadata/finalizers"},
                        ]
                    ),
                )

    def after_namespace(self, run):
        if run["level"] != 124:
            return
        data = self.identity(run)
        if not data:
            return
        r = self.r
        name = "dq-record-" + run["id"]
        directory = "/var/local/dq-" + r.installation + "/" + run["id"]
        found = []
        if data.get("name") != name or data.get("directory") != directory:
            raise RuntimeError("Refusing a changed local-volume path")
        for kind in (
            "persistentvolume",
            "storageclass",
            "clusterrolebinding",
            "clusterrole",
        ):
            text = r.kube(
                "get", kind, name, "--ignore-not-found", "-o", "json"
            ).stdout.strip()
            if text:
                item = json.loads(text)
                if any(
                    item["metadata"].get("labels", {}).get(k) != v
                    for k, v in self.labels(run).items()
                ):
                    raise RuntimeError("Refusing foreign storage resources")
                if kind == "persistentvolume" and (
                    item["metadata"]["uid"] != data["pv_uid"]
                    or item["spec"].get("local", {}).get("path") != directory
                ):
                    raise RuntimeError("Refusing a replaced local volume")
                found.append(kind)
        for kind in found:
            r.kube("delete", kind, name, "--wait=true", "--timeout=45s", timeout=55)
        node = owned_node(r, run)
        r.docker("exec", node, "rm", "-rf", "--", directory)
