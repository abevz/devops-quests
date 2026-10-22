"""Check intended public source; local state/dependencies are never publication inputs."""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def audit(root=ROOT):
    raw = subprocess.check_output(
        ["git", "ls-files", "-c", "-o", "--exclude-standard", "-z"], cwd=root
    )
    errors = []
    unrelated = "gram" + "mar"
    private_domain = "be" + "vz.net"
    for name in set(raw.decode().split("\0")) - {""}:
        path = root / name
        if not path.exists():
            continue
        if path.is_symlink() or path.suffix in {
            ".db",
            ".sqlite3",
            ".key",
            ".p12",
            ".pfx",
        }:
            errors.append(name + ": private/generated file type")
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        forbidden = [
            unrelated,
            private_domain,
            "vm" + "116",
            "vm" + "105",
            "/home/" + "ab" + "evz",
            "vault=" + "mo" + "onbase",
            "co-authored" + "-by:",
        ]
        for token in forbidden:
            if token.lower() in text.lower():
                errors.append(name + ": forbidden private reference")
        if re.search(
            r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\n[A-Za-z0-9+/]", text
        ):
            errors.append(name + ": embedded private key")
        if re.search(r"\b10\.10\.10\.\d+\b", text):
            errors.append(name + ": personal network address")
    return sorted(set(errors))


if __name__ == "__main__":
    errors = audit()
    for error in errors:
        print(error)
    if errors:
        raise SystemExit(1)
    print("Public source hygiene passed")
