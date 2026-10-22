"""Headed UI test server with a separate synthetic profile database."""

import argparse
import fcntl
from pathlib import Path

from aiohttp import web

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.runtime import Runtime
from devops_quests.server import make_app
from devops_quests.store import Store


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, default=ROOT / ".state/ui-fixture")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--public-origin")
    parser.add_argument(
        "--allowed-host", action="append", default=["127.0.0.1", "localhost"]
    )
    args = parser.parse_args()
    runtime = Runtime(ROOT / ".state/runtime")
    installation_lock = (runtime.state / "server.lock").open("a")
    try:
        fcntl.flock(installation_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("Stop other sandbox users before the UI fixture") from None
    store = Store(args.profile / "progress.db")
    store.bootstrap()
    for run in store.active():
        runtime.teardown(run)
        store.update(run, status="interrupted", ended=store.clock())
    catalog = Catalog()
    engine = Engine(store, catalog, runtime)
    web.run_app(
        make_app(
            store,
            catalog,
            engine,
            base="/devops/",
            hosts=set(args.allowed_host),
            public_origin=args.public_origin,
        ),
        host="127.0.0.1",
        port=args.port,
    )


if __name__ == "__main__":
    main()
