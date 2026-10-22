"""Recovery, observation and generated applications keep their ownership boundaries."""

import json
from types import SimpleNamespace

import pytest

from devops_quests.application_sets import ApplicationSets
from devops_quests.prometheus import Prometheus
from devops_quests.recovery_fixtures import FINALIZER, RecoveryFixtures

RUN = {"id": "a" * 24, "level": 123}


class FixtureRuntime:
    installation = "fixture"

    def __init__(self, state):
        self.state = state
        self.calls = []
        self.images = {"prometheus": "prometheus@sha256:fixture"}
        self.request = "{}"
        self.existing = ""

    def namespace(self, run):
        return "dq-" + run["id"]

    def exec(self, run, command, **kwargs):
        return SimpleNamespace(returncode=0, stdout=self.request)

    def kube(self, *args, input=None, **kwargs):
        self.calls.append((args, json.loads(input) if input else None))
        return SimpleNamespace(stdout=self.existing)

    def load_image(self, name):
        self.calls.append((("load", name), None))


def test_application_set_submission_cannot_change_scope_or_use_other_generators(
    tmp_path,
):
    runtime = FixtureRuntime(tmp_path)
    adapter = ApplicationSets(runtime)
    for field, value in (
        ("project", "default"),
        ("destination", {"namespace": "foreign"}),
    ):
        request = adapter.manifest(RUN, True)
        request["spec"]["template"]["spec"][field] = value
        runtime.request = json.dumps(request)
        adapter.control(RUN)
    request = adapter.manifest(RUN, True)
    request["spec"]["generators"] = [
        {"scmProvider": {"github": {"organization": "external"}}}
    ]
    runtime.request = json.dumps(request)
    adapter.control(RUN)
    assert runtime.calls == []


def test_application_set_refuses_replaced_uid_before_applying(tmp_path):
    runtime = FixtureRuntime(tmp_path)
    adapter = ApplicationSets(runtime)
    runtime.request = json.dumps(adapter.manifest(RUN, True))
    path = tmp_path / "bays" / RUN["id"] / "appset-identity.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({"uid": "original"}))
    runtime.existing = json.dumps(
        {"metadata": {"uid": "replacement", "labels": adapter.labels(RUN)}}
    )
    with pytest.raises(RuntimeError, match="replaced"):
        adapter.control(RUN)
    assert not any(args[0] == "apply" for args, _ in runtime.calls)


@pytest.mark.parametrize("failure", ["replacement", "unknown-finalizer"])
def test_finalizer_cleanup_preflights_before_any_mutation(tmp_path, failure):
    run = dict(RUN, level=129)
    runtime = FixtureRuntime(tmp_path)
    adapter = RecoveryFixtures(runtime)
    adapter.path(run).parent.mkdir(parents=True)
    adapter.save(
        run,
        {
            "installation": runtime.installation,
            "run": run["id"],
            "level": 129,
            "parent_uid": "parent",
            "child_uid": "child",
            "control_uid": "control",
        },
    )

    def kube(*args, **kwargs):
        runtime.calls.append((args, kwargs))
        assert args[2] == "get"
        is_parent = args[3] == "configmap"
        metadata = {
            "uid": "parent" if is_parent else "child",
            "labels": adapter.labels(run),
        }
        if is_parent:
            metadata["finalizers"] = [
                FINALIZER if failure != "unknown-finalizer" else "foreign/finalizer"
            ]
        elif failure == "replacement":
            metadata["uid"] = "replacement"
        return SimpleNamespace(stdout=json.dumps({"metadata": metadata}))

    runtime.kube = kube
    with pytest.raises(RuntimeError, match="replaced|unknown finalizer"):
        adapter.before_namespace(run)
    assert all(args[2] == "get" for args, _ in runtime.calls)


def test_storage_cleanup_refuses_changed_directory_without_node_or_api_access(tmp_path):
    run = dict(RUN, level=124)
    runtime = FixtureRuntime(tmp_path)
    adapter = RecoveryFixtures(runtime)
    adapter.path(run).parent.mkdir(parents=True)
    adapter.save(
        run,
        {
            "installation": runtime.installation,
            "run": run["id"],
            "level": 124,
            "name": "dq-record-" + run["id"],
            "directory": "/foreign",
        },
    )
    with pytest.raises(RuntimeError, match="path"):
        adapter.after_namespace(run)
    assert runtime.calls == []


def test_prometheus_has_one_private_target_no_credentials_and_bounded_storage(tmp_path):
    import yaml

    runtime = FixtureRuntime(tmp_path)
    Prometheus(runtime).create(dict(RUN, level=127))
    objects = [item for _, item in runtime.calls if item]
    config = next(item for item in objects if item["kind"] == "ConfigMap")
    scrape = yaml.safe_load(config["data"]["prometheus.yml"])["scrape_configs"]
    assert scrape == [
        {
            "job_name": "board",
            "metrics_path": "/metrics.txt",
            "static_configs": [
                {"targets": ["board." + runtime.namespace(RUN) + ".svc:8080"]}
            ],
        }
    ]
    pod = next(item for item in objects if item["kind"] == "Deployment")["spec"][
        "template"
    ]["spec"]
    assert pod["automountServiceAccountToken"] is False
    assert pod["volumes"][1] == {"name": "data", "emptyDir": {"sizeLimit": "64Mi"}}
    assert pod["containers"][0]["resources"]["limits"] == {
        "cpu": "300m",
        "memory": "256Mi",
    }
    assert not any(
        item["kind"] in {"Role", "RoleBinding", "ClusterRole", "ClusterRoleBinding"}
        for item in objects
    )
