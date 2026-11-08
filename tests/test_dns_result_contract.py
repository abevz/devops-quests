"""105 observes the resolver response while retaining its explicit runtime/exposure contract."""

import json
import os
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "different-corefile-ttl",
        "extra-dns-record",
        "formatted-answer",
        "wrong-answer",
        "server-address-only",
        "wrong-runtime",
        "missing-tcp",
        "extra-port",
        "malformed",
    ],
)
def test_private_resolver_checks_response_not_corefile_spelling(tmp_path, variant):
    quest = tmp_path / "quest"
    quest.mkdir()
    binary = tmp_path / "bin"
    binary.mkdir()
    deployment = {
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "name": "worker",
                            "command": ["/coredns"],
                            "args": ["-conf", "/etc/station/Corefile"],
                        }
                    ]
                }
            }
        }
    }
    service = {
        "spec": {
            "clusterIP": "10.0.0.53",
            "ports": [
                {"port": 53, "targetPort": 1053, "protocol": "UDP"},
                {"port": 53, "targetPort": 1053, "protocol": "TCP"},
            ],
        }
    }
    if variant == "wrong-runtime":
        deployment["spec"]["template"]["spec"]["containers"][0]["command"] = [
            "/bin/false"
        ]
    if variant == "missing-tcp":
        service["spec"]["ports"].pop()
    if variant == "extra-port":
        service["spec"]["ports"].append({"port": 8080, "targetPort": 8080})
    (quest / "deployment.json").write_text(json.dumps(deployment))
    (quest / "service.json").write_text(json.dumps(service))
    (quest / "variant").write_text(variant)
    receipt = tmp_path / "expected-dns-address"
    receipt.write_text("10.0.0.10\n")
    kubectl = binary / "kubectl"
    kubectl.write_text(
        "#!"
        + sys.executable
        + "\n"
        + """import pathlib,sys
args=sys.argv[1:];variant=pathlib.Path('variant').read_text()
if args[:3]==['get','deployment','station-dns']:
 print('malformed' if variant=='malformed' else pathlib.Path('deployment.json').read_text())
elif args[:3]==['get','service','station-dns']:print(pathlib.Path('service.json').read_text())
elif 'nslookup' in args:
 assert args[-1]=='10.0.0.53'
 if variant=='server-address-only': print('Server: 10.0.0.10\\nAddress: 10.0.0.10:53')
 else:
  print('Server: 10.0.0.53\\nAddress: 10.0.0.53:53\\nName: north.station.internal')
  print(('Address 1: ' if variant=='formatted-answer' else 'Address: ')+('10.0.0.99' if variant=='wrong-answer' else '10.0.0.10'))
else:raise RuntimeError('This observation must not parse Corefile directives: '+repr(args))
"""
    )
    kubectl.chmod(0o755)
    check = yaml.safe_load((ROOT / "quests/105/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][0]["check"].replace("/run/dq/facts/0/expected-dns-address", str(receipt))
    result = subprocess.run(
        ["bash", "-c", check],
        env={
            **os.environ,
            "HOME": str(tmp_path),
            "PATH": str(binary) + ":" + os.environ["PATH"],
        },
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert (result.returncode == 0) is (
        variant
        in {
            "reference",
            "different-corefile-ttl",
            "extra-dns-record",
            "formatted-answer",
        }
    ), result.stdout + result.stderr
    assert "Traceback" not in result.stdout + result.stderr
    if result.returncode:
        assert "[DQ:" in result.stdout
