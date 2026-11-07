"""CPU proof comes from the live serving container, never the mutable worksheet."""

import os
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


def check():
    return yaml.safe_load((ROOT / "quests/094/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][3]["check"]


@pytest.mark.parametrize(
    "sample,body,accepted",
    [
        ("0", "north-94", True),
        ("5", "north-94", True),
        ("6", "north-94", False),
        ("20", "north-94", False),
        ("0", "wrong", False),
        ("garbage", "north-94", False),
    ],
)
def test_cpu_sampling_and_http_are_both_required(tmp_path, sample, body, accepted):
    executable = tmp_path / "kubectl"
    executable.write_text("""#!/usr/bin/env python3
import os,sys
assert sys.argv[1:6]==['exec','--pod-running-timeout=2s','deployment/board','-c','worker']
if 'wget' in sys.argv:print(os.environ['DQ_TEST_HTTP'])
else:
 assert 'cpu.stat' in sys.argv[-1] and 'sleep 2' in sys.argv[-1]
 print(os.environ['DQ_TEST_SAMPLE'])
""")
    executable.chmod(0o755)
    # A forged worksheet must not replace the trusted runtime counter sample.
    (tmp_path / "measure.sh").write_text("echo 0\n")
    env = {
        **os.environ,
        "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
        "DQ_TEST_SAMPLE": sample,
        "DQ_TEST_HTTP": body,
    }
    result = subprocess.run(
        ["bash", "-c", check()],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert (result.returncode == 0) is accepted


@pytest.mark.parametrize(
    "sample,accepted",
    [
        ("0", True),
        ("5", True),
        ("005", True),
        ("6", False),
        ("-1", False),
        ("garbage", False),
        ("", False),
    ],
)
def test_worksheet_output_must_be_a_valid_nonnegative_sample(
    tmp_path, sample, accepted
):
    quest = yaml.safe_load((ROOT / "quests/094/quest.yaml").read_text())
    source = quest["stages"][0]["objectives"][5]["check"]
    (tmp_path / "measure.sh").write_text('printf "%s\\n" "$DQ_TEST_SAMPLE"\n')
    result = subprocess.run(
        ["bash", "-c", source],
        cwd=tmp_path,
        env={**os.environ, "DQ_TEST_SAMPLE": sample},
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert (result.returncode == 0) is accepted
