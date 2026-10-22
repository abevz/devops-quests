import json
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
os.environ["ANSIBLE_NOCOLOR"] = "1"
os.environ["ANSIBLE_CONFIG"] = str(pathlib.Path.home() / "lab/ansible.cfg")
for name in ["/tmp/ansible-visual-guide", "/tmp/ansible-revision-jRYkFm"]:
    pathlib.Path(name).mkdir(exist_ok=True)
results = []
for case in json.loads((root / "cases.json").read_text()):
    path = root / case["directory"]
    if case["prepare"] and not (path / "secret.yml").read_text().startswith(
        "$ANSIBLE_VAULT"
    ):
        subprocess.run(
            ["/bin/bash", "-c", case["prepare"]],
            cwd=path,
            check=True,
            capture_output=True,
        )
    flags = [
        str(pathlib.Path.home() / "lab/inventory.ini")
        if s == "__LAB_INVENTORY__"
        else s
        for s in case["flags"]
    ]
    result = subprocess.run(
        ["ansible-playbook", "-i", "inventory.ini", "playbook.yaml", *flags],
        cwd=path,
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    text = result.stdout + result.stderr
    (path / "result.log").write_text(text)
    ok = (
        result.returncode == case["expected_exit"]
        and all(s in text for s in case["contains"])
        and not any(s in text for s in case["absent"])
    )
    results.append(
        {
            "directory": case["directory"],
            "source_block": case["source_block"],
            "exit": result.returncode,
            "passed": ok,
        }
    )
    print(
        case["directory"],
        "PASS" if ok else "FAIL",
        "exit",
        result.returncode,
        flush=True,
    )
    if not ok:
        print(text, flush=True)
(root / "results.json").write_text(json.dumps(results, indent=2))
if not all(r["passed"] for r in results):
    sys.exit(1)
