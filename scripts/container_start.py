"""Trusted backend startup; persistent paths match the host Docker daemon."""

import os
import shutil
import subprocess
from pathlib import Path

root = Path.cwd()
if os.uname().machine != "x86_64" or not Path("/var/run/docker.sock").is_socket():
    raise SystemExit("Native Linux amd64 with the host Docker socket is required")
bundles = Path("/opt/devops-quests/web/vendor")
(root / "web/vendor").mkdir(parents=True, exist_ok=True)
for path in bundles.iterdir():
    if path.is_file() and path.resolve() != (root / "web/vendor" / path.name).resolve():
        shutil.copy2(path, root / "web/vendor" / path.name)
subprocess.run(["python3", "scripts/prepare_assets.py"], check=True, cwd=root)
os.execvp(
    "python3",
    [
        "python3",
        "-m",
        "devops_quests",
        "serve",
        "--port",
        os.environ.get("DQ_PORT", "8766"),
    ],
)
