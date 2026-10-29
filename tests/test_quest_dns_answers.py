"""DNS checks must inspect complete answer addresses, not substrings or the server."""

import subprocess

import pytest

from devops_quests.catalog import ROOT


@pytest.mark.parametrize(("number", "stage"), [(105, 0), (106, 0), (110, 0), (110, 1)])
@pytest.mark.parametrize(
    ("answer", "accepted"),
    [
        ("Server: dns\nAddress: 10.0.0.3:53\n\nName: station\nAddress: 10.0.0.30\n", False),
        ("Server: dns\nAddress: 10.0.0.3:53\n\nName: station\nAddress: 10.0.0.3\n", True),
        ("Server: dns\nAddress: 10.0.0.3:53\n", False),
    ],
)
def test_only_exact_dns_answer_addresses_count(number, stage, answer, accepted):
    source = (ROOT / f"quests/{number:03}/check-{stage}.sh").read_text()
    function = "dns_answer_has() {\n" + source.split("dns_answer_has() {\n", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
    result = subprocess.run(
        ["bash", "-c", function + 'dns_answer_has "$1" "$2"', "--", answer, "10.0.0.3"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert (result.returncode == 0) is accepted
