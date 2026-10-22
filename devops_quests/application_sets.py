"""Bounded submission of a real, namespace-scoped ApplicationSet."""

import json

from .components import Components
from .platform import Platform
from .sandbox_evidence import CONTROL_READER


class ApplicationSets(Components):
    def manifest(self, run, repaired=False):
        self.namespace(run)
        return {
            "apiVersion": "argoproj.io/v1alpha1",
            "kind": "ApplicationSet",
            "metadata": {
                "name": "station",
                "namespace": Platform(self.r).namespace(run),
            },
            "spec": {
                "goTemplate": True,
                "goTemplateOptions": ["missingkey=error"],
                "generators": [
                    {"list": {"elements": [{"station": "north"}, {"station": "south"}]}}
                ],
                "template": {
                    "metadata": {"name": "{{.station}}"},
                    "spec": {
                        "project": "station",
                        "source": {
                            "repoURL": "http://gitea-"
                            + run["id"]
                            + ":3000/rail/station.git",
                            "targetRevision": "main",
                            "path": ("stations/" if repaired else "retired/")
                            + "{{.station}}",
                        },
                        "destination": {
                            "server": "https://kubernetes.default.svc",
                            "namespace": self.r.namespace(run),
                        },
                        "syncPolicy": {"automated": {"prune": True, "selfHeal": True}},
                    },
                },
                "syncPolicy": {"preserveResourcesOnDeletion": True},
            },
        }

    def create(self, run):
        r = self.r
        self.namespace(run)
        ns = Platform(r).namespace(run)
        rbac = "rbac.authorization.k8s.io/v1"
        name = "appset-reader"
        role = {
            "apiVersion": rbac,
            "kind": "Role",
            "metadata": {"name": name, "namespace": ns, "labels": self.labels(run)},
            "rules": [
                {
                    "apiGroups": ["argoproj.io"],
                    "resources": ["applicationsets"],
                    "resourceNames": ["station"],
                    "verbs": ["get"],
                },
                {
                    "apiGroups": ["argoproj.io"],
                    "resources": ["applications"],
                    "resourceNames": ["north", "south"],
                    "verbs": ["get"],
                },
            ],
        }
        binding = {
            "apiVersion": rbac,
            "kind": "RoleBinding",
            "metadata": {"name": name, "namespace": ns, "labels": self.labels(run)},
            "roleRef": {
                "apiGroup": "rbac.authorization.k8s.io",
                "kind": "Role",
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
            "appset-target.json",
            json.dumps(
                {
                    "namespace": ns,
                    "repoURL": "http://gitea-" + run["id"] + ":3000/rail/station.git",
                }
            ),
        )

    def control(self, run):
        r = self.r
        self.namespace(run)
        ns = Platform(r).namespace(run)
        result = r.exec(
            run,
            "/usr/bin/python3 - applicationset.json <<'APPSET_CONTROL'\n"
            + CONTROL_READER
            + "\nAPPSET_CONTROL\n",
            check=False,
            timeout=3,
        )
        if result.returncode:
            return
        try:
            request = json.loads(result.stdout)
        except ValueError:
            return
        if request not in [self.manifest(run), self.manifest(run, True)]:
            return
        path = r.state / "bays" / run["id"] / "appset-identity.json"
        raw = r.kube(
            "-n",
            ns,
            "get",
            "applicationset",
            "station",
            "--ignore-not-found",
            "-o",
            "json",
        ).stdout.strip()
        if raw:
            item = json.loads(raw)
            if (
                not path.exists()
                or json.loads(path.read_text())["uid"] != item["metadata"]["uid"]
                or any(
                    item["metadata"].get("labels", {}).get(k) != v
                    for k, v in self.labels(run).items()
                )
            ):
                raise RuntimeError("Refusing a replaced ApplicationSet")
        elif path.exists():
            raise RuntimeError("The original ApplicationSet was removed")
        request["metadata"]["labels"] = self.labels(run)
        r.kube("apply", "-f", "-", input=json.dumps(request))
        if not raw:
            uid = json.loads(
                r.kube(
                    "-n", ns, "get", "applicationset", "station", "-o", "json"
                ).stdout
            )["metadata"]["uid"]
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps({"uid": uid}))
            temporary.chmod(0o600)
            temporary.replace(path)
