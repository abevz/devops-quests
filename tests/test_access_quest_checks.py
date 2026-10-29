"""Access checks must protect tokens and explain each observed denial."""

import json
import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT, Catalog


def run_access_check(tmp_path, number, *, deny=True):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    facts = tmp_path / "facts"
    facts.mkdir()
    (facts / "api-endpoint").write_text("https://private.invalid")
    binaries = tmp_path / "bin"
    binaries.mkdir()
    role = {"rules": [{"apiGroups": [""], "resources": ["configmaps"], "resourceNames": ["route"], "verbs": ["get"]}]}
    reader = {
        "spec": {"template": {"spec": {
            "automountServiceAccountToken": False,
            "volumes": [{"projected": {"sources": [{"serviceAccountToken": {
                "path": "token", "expirationSeconds": 600,
                "audience": "https://kubernetes.default.svc.cluster.local",
            }}]}}],
        }}}
    }
    binding = {"subjects": [{"kind": "ServiceAccount", "name": "controller", "namespace": "test"}]}
    kubectl = f'''case "$1 $2" in
    "get deployment") printf '%s\\n' '{json.dumps(reader)}' ;;
    "get role") printf '%s\\n' '{json.dumps(role)}' ;;
    "get rolebinding") printf '%s\\n' '{json.dumps(binding)}' ;;
    "exec --pod-running-timeout=2s")
      if [[ "$*" == *deployment/observer* ]]; then printf observer.synthetic.token; else printf controller.synthetic.token; fi ;;
    *) exit 1 ;;
    esac
'''
    curl = f'''if [[ "$*" == *synthetic.token* ]]; then exit 90; fi
header=$(cat)
out=/dev/null
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out=$2; shift 2; else url=$1; shift; fi
done
if [[ "$url" == */configmaps/route && "$header" != *observer.synthetic.token* ]]; then
  printf '%s' '{{"data":{{"route":"north-{number}"}}}}' > "$out"; printf 200
else
  printf '{403 if deny else 200}'
fi
'''
    for name, text in (("kubectl", kubectl), ("curl", curl)):
        path = binaries / name
        path.write_text("#!/bin/bash\n" + text)
        path.chmod(0o755)
    source = (ROOT / f"quests/{number}/check-0.sh").read_text().replace("/run/dq/facts/0", str(facts))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NAMESPACE": "test"}
    return subprocess.run(["bash", "-c", source], env=environment, text=True, capture_output=True, timeout=15)


@pytest.mark.parametrize("number", (114, 125))
def test_real_request_shape_uses_stdin_and_accepts_expected_access(tmp_path, number):
    result = run_access_check(tmp_path, number)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "synthetic.token" not in result.stdout + result.stderr


@pytest.mark.parametrize(("number", "expected"), [(114, 3), (125, 5)])
def test_every_incorrect_denial_has_a_translatable_diagnostic(tmp_path, number, expected):
    result = run_access_check(tmp_path, number, deny=False)
    assert result.returncode != 0
    assert "synthetic.token" not in result.stdout + result.stderr
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert len(markers) == expected == len(result.stdout.splitlines())
    diagnostics = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}


def test_security_failures_have_localized_markers(tmp_path):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text("#!/bin/bash\nexit 1\n")
    kubectl.chmod(0o755)
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NAMESPACE": "test"}
    result = subprocess.run(["bash", str(ROOT / "quests/109/check-0.sh")], env=environment, text=True, capture_output=True, timeout=15)
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()) == 24
    diagnostics = Catalog().public(109)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}
