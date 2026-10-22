"""Persistent learning workspaces, independent of quest attempts and scores."""

import asyncio
import hashlib
import logging
from pathlib import Path

import yaml

log = logging.getLogger(__name__)


class LabCatalog:
    def __init__(self, root):
        self.root = Path(root)
        self.profiles = yaml.safe_load((self.root / "labs/profiles.yaml").read_text())
        for name, profile in self.profiles.items():
            digest = hashlib.sha256(yaml.safe_dump(profile, sort_keys=True).encode())
            for relative in (
                "images.lock.json",
                "labs/images.lock.json",
                "labs/collections.lock.json",
                ".state/lab-images.json",
                ".state/built-image.json",
                ".state/kind-image.json",
                ".state/host-images.json",
                "devops_quests/lab_runtime.py",
                "devops_quests/lab_create.py",
                "devops_quests/runtime.py",
                "devops_quests/platform.py",
            ):
                path = self.root / relative
                if path.exists():
                    digest.update(path.read_bytes())
            for path in sorted((self.root / "labs/examples" / name).rglob("*")):
                if path.is_file():
                    digest.update(str(path.relative_to(self.root)).encode())
                    digest.update(path.read_bytes())
            profile["version"] += ":" + digest.hexdigest()[:16]

    def profile(self, name):
        if not isinstance(name, str) or name not in self.profiles:
            raise ValueError("error.lab_profile")
        return self.profiles[name]

    def public(self):
        return [
            dict(
                id=name,
                **{key: data[key] for key in ("title", "description", "version")},
            )
            for name, data in self.profiles.items()
        ]


class LabManager:
    def __init__(self, store, engine, catalog, factory):
        self.store, self.engine, self.catalog = store, engine, catalog
        self.factory = factory
        self.tasks = {}

    def get(self, user, identifier):
        lab = self.store.lab(identifier, user)
        if not lab:
            raise ValueError("error.lab_missing")
        return lab

    async def create(self, user, profile):
        spec = self.catalog.profile(profile)
        lab = self.store.save_lab(user, profile, spec["version"])
        return await self.action(user, lab["id"], "start")

    async def action(self, user, identifier, action, confirmation=None):
        if not isinstance(action, str) or action not in {
            "start",
            "stop",
            "reset",
            "delete",
        }:
            raise ValueError("error.request")
        async with self.engine.start_lock:
            lab = self.get(user, identifier)
            if identifier in self.tasks:
                raise ValueError("error.lab_working")
            if action in {"reset", "delete"} and confirmation != identifier:
                raise ValueError("error.lab_confirm")
            spec = self.catalog.profile(lab["profile"])
            if action in {"start", "reset"} and lab["version"] != spec["version"]:
                raise ValueError("error.lab_version")
            if action == "start":
                if lab["status"] == "running":
                    return lab
                self.store.reserve_lab(lab)
            elif action == "reset":
                # Rebuilding consumes the same shared compute slot as starting.
                self.store.reserve_lab(lab)
            else:
                self.store.update_lab(
                    lab, status="stopping" if action == "stop" else "deleting"
                )
            self.tasks[identifier] = asyncio.create_task(self._perform(lab, action))
            return self.get(user, identifier)

    async def _perform(self, lab, action):
        try:
            runtime = self.factory(lab)
            if action in {"delete", "reset"}:
                await asyncio.to_thread(runtime.delete, lab)
            if action in {"start", "reset"}:
                await asyncio.to_thread(runtime.start, lab)
                self.store.update_lab(lab, status="running", slot=1, error="")
            else:
                if action == "stop":
                    await asyncio.to_thread(runtime.stop, lab)
                self.store.update_lab(
                    lab,
                    status="deleted" if action == "delete" else "stopped",
                    slot=0,
                    error="",
                )
        except Exception:
            log.exception("Lab operation failed: %s %s", lab["id"], action)
            # Never delete saved work on failure, nor advertise free capacity
            # until the runtime has positively stopped all its resources.
            stopped = False
            try:
                await asyncio.to_thread(self.factory(lab).stop, lab)
                stopped = True
            except Exception:
                log.exception("Lab could not be stopped: %s", lab["id"])
            self.store.update_lab(
                lab,
                status="error",
                slot=0 if stopped else 1,
                error="error.lab_operation",
            )
        finally:
            self.tasks.pop(lab["id"], None)

    async def recover(self):
        """A restart pauses saved work; it never destroys it or starts it silently."""
        for lab in self.store.labs():
            if not lab["slot"] and lab["status"] not in {
                "preparing",
                "stopping",
                "deleting",
            }:
                continue
            try:
                await asyncio.to_thread(self.factory(lab).stop, lab)
                self.store.update_lab(lab, status="stopped", slot=0, error="")
            except Exception:
                log.exception("Lab restart recovery failed: %s", lab["id"])
                self.store.update_lab(
                    lab, status="error", slot=1, error="error.lab_operation"
                )

    async def shutdown(self):
        if self.tasks:
            await asyncio.gather(*tuple(self.tasks.values()))
        await self.recover()

    async def stop_user(self, user):
        pending = [
            self.tasks[lab["id"]]
            for lab in self.store.labs(user)
            if lab["id"] in self.tasks
        ]
        if pending:
            await asyncio.gather(*pending)
        for lab in self.store.labs(user, occupied=True):
            await self.action(user, lab["id"], "stop")
        pending = [
            self.tasks[lab["id"]]
            for lab in self.store.labs(user)
            if lab["id"] in self.tasks
        ]
        if pending:
            await asyncio.gather(*pending)


class LabTerminalStore:
    """The shared PTY authenticates against Lab state, never a quest row."""

    def __init__(self, store):
        self.store, self.clock, self.session = store, store.clock, store.session

    def run(self, identifier, user):
        lab = self.store.lab(identifier, user)
        if lab:
            return dict(
                lab, status="active" if lab["status"] == "running" else lab["status"]
            )

    def update(self, lab, **fields):
        # Labs have no idle expiry or command scoring; PTY auth still touches
        # the user's login session via the shared TerminalHub implementation.
        pass


class ScopedLabTerminalEngine:
    def __init__(self, runtime):
        self.runtime = runtime

    def command(self, lab, text):
        pass
