"""Renamed 122 manifests still receive real repository and bay scope values."""

import os
import re
import subprocess

import yaml

from devops_quests.catalog import ROOT


def test_122_yaml_manifests_receive_supplied_repository_and_namespace(tmp_path):
    source = (ROOT / "quests/122/setup-0.sh").read_text()
    script = re.search(r"python3 - <<'TARGETS'\n(.*?)\nTARGETS", source, re.S).group(1)
    paths = [tmp_path / "parent.yaml", tmp_path / "repository/apps/child.yaml"]
    document = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "spec": {
            "source": {"repoURL": "__GIT_URL__"},
            "destination": {"namespace": "__NAMESPACE__"},
        },
    }
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(document))
    protected = tmp_path / "repository/.git/fixture.yaml"
    protected.parent.mkdir()
    protected.write_text("__NAMESPACE__")
    subprocess.run(
        ["python3", "-c", script],
        cwd=tmp_path,
        env={**os.environ, "GIT_URL": "http://gitea.synthetic/rail/station.git", "DQ_NAMESPACE": "dq-synthetic"},
        check=True,
        capture_output=True,
        text=True,
    )
    for path in paths:
        observed = yaml.safe_load(path.read_text())
        assert observed["spec"]["source"]["repoURL"] == "http://gitea.synthetic/rail/station.git"
        assert observed["spec"]["destination"]["namespace"] == "dq-synthetic"
        assert "__GIT_URL__" not in path.read_text()
        assert "__NAMESPACE__" not in path.read_text()
    assert protected.read_text() == "__NAMESPACE__"
