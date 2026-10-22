"""Loopback-only service entrypoint and installation-scoped maintenance."""

import argparse
import fcntl
import getpass
import os
import sys
from pathlib import Path

from aiohttp import web

from .catalog import ROOT, Catalog
from .engine import Engine
from .lab_runtime import LabRuntime
from .labs import LabCatalog, LabManager
from .runtime import Runtime
from .server import make_app
from .store import Store


def main():
    parser = argparse.ArgumentParser(description="Private DevOps training bays")
    parser.add_argument(
        "action",
        choices=("serve", "reset", "backup", "init-admin"),
        nargs="?",
        default="serve",
    )
    parser.add_argument("--state", type=Path, default=ROOT / ".state/runtime")
    parser.add_argument("--host", default="127.0.0.1", choices=("127.0.0.1", "::1"))
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--base", default="/")
    parser.add_argument(
        "--allowed-host", action="append", default=["127.0.0.1", "localhost", "::1"]
    )
    parser.add_argument(
        "--public-origin", help="Exact external origin behind a trusted reverse proxy"
    )
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--username", help="Explicit first administrator name")
    parser.add_argument("--password-stdin", action="store_true")
    args = parser.parse_args()
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    server_lock = None
    if args.action in {"serve", "reset"}:
        server_lock = (args.state / "server.lock").open("a")
        try:
            fcntl.flock(server_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error(
                "This installation is running; stop its app before serving or resetting."
            )
    store = Store(args.state / "progress.db")
    if args.action == "init-admin":
        if not args.username:
            parser.error("init-admin requires --username; no default account exists")
        password = (
            sys.stdin.readline().rstrip("\r\n")
            if args.password_stdin
            else getpass.getpass("New password (12–128 characters): ")
        )
        try:
            created = store.initialize_admin(args.username, password)
        except ValueError as error:
            parser.error(str(error))
        if not created:
            parser.error("Accounts already exist; no account or password was changed")
        print("First administrator created. Password was not saved to a file.")
        return
    runtime = Runtime(args.state)
    if args.action == "reset":
        runtime.reset()
        for run in store.active():
            store.update(run, status="reset", ended=store.clock())
        print(
            "Training Bay resources removed; profiles, progress and saved Labs retained."
        )
        return
    if args.action == "backup":
        if not args.destination:
            parser.error("--destination is required for backup")
        store.backup(args.destination)
        print(
            "Database backup integrity_check: ok. Lab files and Docker volumes are not included."
        )
        return
    name, password = (
        os.environ.get("DQ_ADMIN_USER"),
        os.environ.get("DQ_ADMIN_PASSWORD"),
    )
    if bool(name) != bool(password):
        parser.error("Set both DQ_ADMIN_USER and DQ_ADMIN_PASSWORD, or neither")
    if name:
        store.initialize_admin(name, password)
    print(
        "WARNING: Web terminal = remote shell inside sandboxes. Run only locally or on a trusted network behind TLS and authentication.",
        flush=True,
    )
    with store.connect() as db:
        if not db.execute("SELECT 1 FROM users LIMIT 1").fetchone():
            print(
                "No accounts exist. Run init-admin --username YOUR_NAME to create the first administrator.",
                flush=True,
            )
    # A previous process may have died while a quest was active. Reclaim only our bays.
    for run in store.active():
        runtime.teardown(run)
        store.update(run, status="interrupted", ended=store.clock())
    engine = Engine(store, Catalog(), runtime)
    profiles = LabCatalog(ROOT)
    labs = LabManager(
        store,
        engine,
        profiles,
        lambda lab: LabRuntime(args.state, ROOT, lab, profiles.profile(lab["profile"])),
    )
    web.run_app(
        make_app(
            store,
            engine.catalog,
            engine,
            args.base,
            set(args.allowed_host),
            args.public_origin,
            labs=labs,
        ),
        host=args.host,
        port=args.port,
    )


if __name__ == "__main__":
    main()
