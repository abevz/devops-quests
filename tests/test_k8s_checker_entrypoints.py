"""Real shell entrypoints tolerate legal metadata and ignore player Python modules."""

import json
import os
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


def deployment(cpu="100m", memory="96Mi", annotation_bytes=0):
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": "board",
            "annotations": {"dq68-proof": "x" * annotation_bytes},
        },
        "spec": {
            "replicas": 1,
            "selector": {"matchLabels": {"app": "board"}},
            "template": {
                "metadata": {"labels": {"app": "board"}},
                "spec": {
                    "containers": [
                        {
                            "name": "worker",
                            "image": "busybox:1.37.0",
                            "resources": {
                                "requests": {"cpu": cpu},
                                "limits": {"cpu": "300m", "memory": memory},
                            },
                        }
                    ]
                },
            },
        },
    }


def execute(tmp_path, number, goal, document, shadow=None):
    fixture = tmp_path / "deployment.json"
    fixture.write_text(json.dumps(document))
    executable = tmp_path / "kubectl"
    executable.write_text("""#!/usr/bin/env python3
import os
from pathlib import Path
print(Path(os.environ['DQ_TEST_DOCUMENT']).read_text())
""")
    executable.chmod(0o755)
    if shadow is not None:
        (tmp_path / "json.py").write_text(
            "def loads(value):\n    return " + repr(shadow) + "\n"
        )
        # The production entrypoint must ignore both cwd and environment import paths.
    env = {
        **os.environ,
        "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
        "DQ_TEST_DOCUMENT": str(fixture),
        "PYTHONPATH": str(tmp_path),
    }
    source = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][goal]["check"]
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", source],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        timeout=8,
    )


@pytest.mark.parametrize("annotation_bytes", [0, 180000])
def test_correct_cpu_property_ignores_legal_unrelated_metadata(
    tmp_path, annotation_bytes
):
    result = execute(tmp_path, 34, 1, deployment(annotation_bytes=annotation_bytes))
    assert result.returncode == 0, result.stdout + result.stderr


def test_wrong_cpu_property_still_fails_with_large_metadata(tmp_path):
    result = execute(tmp_path, 34, 1, deployment(cpu="200m", annotation_bytes=180000))
    assert result.returncode != 0
    assert "Argument list too long" not in result.stderr


@pytest.mark.parametrize(
    "actual,forged,accepted", [("96Mi", "128Mi", True), ("128Mi", "96Mi", False)]
)
def test_player_module_cannot_change_the_live_memory_result(
    tmp_path, actual, forged, accepted
):
    result = execute(
        tmp_path, 88, 0, deployment(memory=actual), shadow=deployment(memory=forged)
    )
    assert (result.returncode == 0) is accepted, result.stdout + result.stderr
