#!/usr/bin/env python3
"""Private online copy; never initialize or migrate the source database."""

import argparse
import os
import sqlite3
import subprocess
from pathlib import Path


def backup(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    if destination.exists():
        raise FileExistsError(destination)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(destination.parent, 0o700)
    # Create privately before sqlite opens it, independent of caller umask.
    with destination.open("xb"):
        os.chmod(destination, 0o600)
    with (
        sqlite3.connect(source.as_uri() + "?mode=ro", uri=True) as reader,
        sqlite3.connect(destination) as writer,
    ):
        reader.backup(writer)
        if writer.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("Backup integrity check failed")
    return destination


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    stamp = subprocess.check_output(
        ["date", "-u", "+%Y%m%dT%H%M%SZ"], text=True
    ).strip()
    target = backup(args.source, args.directory / (stamp + "-progress.db"))
    print("DevOps Quests backup integrity: ok; " + str(target))


if __name__ == "__main__":
    main()
