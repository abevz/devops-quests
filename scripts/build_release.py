"""Build an immutable source/runtime tarball and checksums; never publish."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tarfile
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
EXCLUDE = {
    ".git",
    ".venv",
    ".state",
    "node_modules",
    "artifacts",
    "dist",
    "build",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    ".playwright-cli",
}


def dependencies(output):
    """Package verified tools, wheels and the original collection archives."""
    from scripts.dependency_assets import verify

    result = {}
    archive = output / "devops-quests-dependencies-linux-amd64.tar.gz"
    wheels = sorted((ROOT / ".ci-cache/wheelhouse").glob("*.whl"))
    if not wheels:
        raise RuntimeError("Missing pinned release wheelhouse")
    with tarfile.open(archive, "w:gz") as tar:
        for name, item in json.loads((ROOT / "tools.lock.json").read_text()).items():
            path = verify(ROOT / "bin" / name, item["binary_sha256"])
            tar.add(path, arcname="bin/" + name, recursive=False)
        for path in wheels:
            tar.add(path, arcname="wheelhouse/" + path.name, recursive=False)
    result[archive.name] = hashlib.sha256(archive.read_bytes()).hexdigest()
    for name, item in json.loads(
        (ROOT / "labs/collections.lock.json").read_text()
    ).items():
        path = verify(ROOT / ".state" / name, item["sha256"])
        shutil.copyfile(path, output / name)
        result[name] = item["sha256"]
    return result


def build(version, output):
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("Expected immutable vX.Y.Z")
    output.mkdir(parents=True, exist_ok=True)
    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--"], cwd=ROOT).returncode:
        raise ValueError("Release source must match the committed tree")
    archive = output / ("devops-quests-" + version + ".tar.gz")
    files = {}
    assets = {}
    with tarfile.open(archive, "w:gz", format=tarfile.PAX_FORMAT) as tar:
        tracked = (
            subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
            .decode()
            .split("\0")
        )
        names = {name for name in tracked if name}
        names.update(
            "web/vendor/" + name
            for name in (
                "terminal.js",
                "markdown.js",
                "mermaid.js",
                "locale.js",
                "xterm.css",
            )
        )
        lock = ROOT / "release-images.lock.json"
        if lock.is_file():
            identity = json.loads(lock.read_text())
            if identity.get("version") != version or identity.get("commit") != commit:
                raise ValueError("Release image lock does not match tag/source commit")
            names.add("release-images.lock.json")
            assets = dependencies(output)
        for name in sorted(names):
            path = ROOT / name
            rel = path.relative_to(ROOT)
            if (
                EXCLUDE.intersection(rel.parts)
                or path.is_symlink()
                or not path.is_file()
                or path.name.startswith(".env")
                or path.suffix in {".pyc", ".db", ".sqlite3"}
            ):
                raise ValueError("Unsafe or missing release input: " + name)
            files[str(rel)] = {
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "executable": bool(path.stat().st_mode & 0o111),
            }
            tar.add(path, arcname=str(rel), recursive=False)
        import io

        metadata = {
            "version": version,
            "commit": commit,
            "architecture": "linux/amd64",
            "files": files,
            "dependencies": assets,
        }
        raw = (json.dumps(metadata, indent=2) + "\n").encode()
        info = tarfile.TarInfo("RELEASE.json")
        info.size = len(raw)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(raw))
    paths = sorted(
        p for p in output.iterdir() if p.is_file() and p.name != "SHA256SUMS"
    )
    (output / "SHA256SUMS").write_text(
        "".join(
            hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n"
            for p in paths
        )
    )
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    print(build(args.version, args.output))
