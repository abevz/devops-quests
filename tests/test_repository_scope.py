"""Repository credential repair must not grant platform-wide Secret access."""

import yaml

from devops_quests.platform import Platform


def test_repository_repair_targets_one_secret_and_one_bay_identity():
    calls = []

    class Runtime:
        def namespace(self, run):
            return "dq-" + run["id"]

        def kube(self, *args, input):
            calls.extend(yaml.safe_load_all(input))

    Platform(Runtime()).repository_access({"id": "fixture"})
    role, binding = calls
    assert role["metadata"]["namespace"] == "dq-platform-fixture"
    assert role["rules"] == [
        {
            "apiGroups": [""],
            "resources": ["secrets"],
            "resourceNames": ["station-repository"],
            "verbs": ["get", "patch", "update"],
        }
    ]
    assert binding["subjects"] == [
        {"kind": "ServiceAccount", "name": "player", "namespace": "dq-fixture"}
    ]
    assert binding["roleRef"]["name"] == role["metadata"]["name"]
