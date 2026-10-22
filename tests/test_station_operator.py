"""The controller cannot adopt unrelated objects or turn input into commands."""

import json
from types import SimpleNamespace

import pytest

from devops_quests.book_runtime import reconcile

RUN = {"id": "a" * 24, "level": 116}


class Runtime:
    def __init__(self):
        self.images = {"app": "busybox@sha256:pinned"}
        self.route = "north-116"
        self.objects = {}
        self.writes = []
        self.foreign = False

    def namespace(self, run):
        return "dq-owned"

    def kube(self, *args, **kwargs):
        if args[0] == "apply":
            item = json.loads(kwargs["input"])
            self.objects[item["kind"]] = item
            self.writes.append(item)
            return SimpleNamespace(stdout="")
        assert args[:2] == ("-n", "dq-owned")
        if args[2:4] == ("get", "stationboard"):
            return SimpleNamespace(
                stdout=json.dumps(
                    {
                        "apiVersion": "training.devops-quests.local/v1",
                        "metadata": {"uid": "owner", "generation": 3},
                        "spec": {"route": self.route},
                    }
                )
            )
        if args[2] == "get":
            kind, _name = args[3:5]
            value = self.objects.get(kind)
            if self.foreign and kind == "ConfigMap":
                value = {"metadata": {"ownerReferences": [{"uid": "foreign"}]}}
            if kind == "deployment":
                value = {"status": {"readyReplicas": 1}}
            return SimpleNamespace(stdout=json.dumps(value) if value else "")
        return SimpleNamespace(stdout="")


@pytest.mark.parametrize(
    "route", ["north; cat /etc/shadow", "http://owner-host", "../outside", "unknown"]
)
def test_operator_ignores_routes_outside_finite_schema(route):
    r = Runtime()
    r.route = route
    reconcile(r, RUN)
    assert not r.writes


def test_operator_refuses_foreign_objects_instead_of_adopting_them():
    r = Runtime()
    r.foreign = True
    with pytest.raises(RuntimeError, match="adopt a foreign"):
        reconcile(r, RUN)
    assert not r.writes


def test_reconciliation_produces_only_scoped_bounded_nonprivileged_workloads():
    r = Runtime()
    reconcile(r, RUN)
    assert len(r.writes) == 3
    assert all(
        o["metadata"]["namespace"] == "dq-owned"
        and o["metadata"]["ownerReferences"][0]["uid"] == "owner"
        for o in r.writes
    )
    dep = r.objects["Deployment"]
    spec = dep["spec"]["template"]["spec"]
    assert (
        not spec["automountServiceAccountToken"]
        and spec["securityContext"]["runAsNonRoot"]
    )
    c = spec["containers"][0]
    assert c["image"] == r.images["app"] and c["resources"]["limits"] == {
        "cpu": "200m",
        "memory": "32Mi",
    }
    assert c["securityContext"]["capabilities"]["drop"] == ["ALL"]
    assert not any("hostPath" in v for v in spec["volumes"])
