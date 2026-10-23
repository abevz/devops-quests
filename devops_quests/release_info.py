"""Server-owned build identity and an explicitly enabled release notice cache."""

import asyncio
import hashlib
import json
import logging
import math
import os
import re
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from importlib import metadata
from pathlib import Path
from urllib.parse import quote

import aiohttp

LOGGER = logging.getLogger(__name__)
DAY = 86400
UPSTREAM = "abevz/devops-quests"
DEPLOY_COMMAND = "sudo /opt/devops-quests/operator/deploy.sh"
SEMVER = re.compile(
    r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\Z"
)
BUILD_TAG = re.compile(
    r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\Z"
)
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}\Z")


def stable_version(value):
    if not isinstance(value, str) or len(value) > 128:
        return None
    match = SEMVER.fullmatch(value)
    return tuple(map(int, match.groups())) if match else None


@dataclass(frozen=True)
class BuildInfo:
    version: str
    commit: str

    def payload(self):
        return asdict(self)

    @classmethod
    def read(cls, root):
        root = Path(root)
        try:
            record = json.loads((root / "RELEASE.json").read_text())
            version, commit = record["version"], record["commit"]
            if (
                isinstance(version, str)
                and len(version) <= 128
                and BUILD_TAG.fullmatch(version)
                and re.fullmatch(r"[a-f0-9]{40}", commit)
            ):
                return cls("v" + version.removeprefix("v"), commit[:7])
        except (OSError, ValueError, KeyError, TypeError):
            pass
        try:
            version = metadata.version("devops-quests")
        except metadata.PackageNotFoundError:
            version = "dev"
        if stable_version(version) is not None:
            version = "v" + version.removeprefix("v")
        commit = "dev"
        if (root / ".git").exists():
            try:
                value = subprocess.check_output(
                    ["git", "-C", str(root), "rev-parse", "--verify", "HEAD"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=1,
                ).strip()
                if re.fullmatch(r"[a-f0-9]{40}", value):
                    commit = value[:7]
            except (OSError, subprocess.SubprocessError):
                pass
        return cls(version, commit)


async def fetch_latest(repository):
    timeout = aiohttp.ClientTimeout(total=5)
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2026-03-10",
        "User-Agent": "DevOps-Quests-update-notice",
    }
    async with aiohttp.ClientSession(timeout=timeout, headers=headers) as client:
        async with client.get(
            f"https://api.github.com/repos/{repository}/releases/latest",
            allow_redirects=False,
        ) as response:
            response.raise_for_status()
            if response.status != 200:
                raise ValueError("Unexpected release API response")
            body = bytearray()
            async for chunk in response.content.iter_chunked(65536):
                body.extend(chunk)
                if len(body) > 1_000_000:
                    raise ValueError("Release API response too large")
            return json.loads(body)


class UpdateChecker:
    def __init__(
        self,
        cache_dir,
        *,
        enabled=False,
        repository=UPSTREAM,
        hint="none",
        command=DEPLOY_COMMAND,
        fetch=None,
        clock=time.time,
    ):
        self.repository = repository
        self.enabled = enabled and bool(REPOSITORY.fullmatch(repository))
        if enabled and not self.enabled:
            LOGGER.info("Update notices disabled: invalid repository setting")
        self.hint = hint if hint in {"deploy", "compose", "none"} else "none"
        self.command = (
            command.strip()
            if isinstance(command, str)
            and len(command) <= 512
            and all(ord(c) >= 32 for c in command)
            else ""
        )
        key = hashlib.sha256(repository.encode()).hexdigest()[:16]
        self.cache = Path(cache_dir) / f"update-check-{key}.json"
        self.fetch = fetch or fetch_latest
        self.clock = clock
        self.checked_at = None
        self.tag = None
        self.lock = asyncio.Lock()
        if self.enabled:
            self._load()

    @classmethod
    def from_environment(cls, cache_dir):
        return cls(
            cache_dir,
            enabled=os.environ.get("DQ_UPDATE_CHECK") == "1",
            repository=os.environ.get("DQ_UPDATE_REPO", UPSTREAM),
            hint=os.environ.get("DQ_UPDATE_HINT", "none"),
            command=os.environ.get("DQ_UPDATE_DEPLOY_COMMAND", DEPLOY_COMMAND),
        )

    def _load(self):
        try:
            if self.cache.stat().st_size > 65536:
                return
            data = json.loads(self.cache.read_text())
            checked = data["checked_at"]
            if (
                data["repository"] != self.repository
                or isinstance(checked, bool)
                or not isinstance(checked, (int, float))
                or not math.isfinite(checked)
            ):
                return
            self.checked_at = checked
            if stable_version(data.get("tag")) is not None:
                self.tag = data["tag"]
        except (OSError, ValueError, TypeError, KeyError):
            pass

    def _save(self):
        self.cache.parent.mkdir(parents=True, exist_ok=True)
        name = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", dir=self.cache.parent, prefix=".update-check-", delete=False
            ) as stream:
                name = stream.name
                json.dump(
                    {
                        "repository": self.repository,
                        "checked_at": self.checked_at,
                        "tag": self.tag,
                    },
                    stream,
                    allow_nan=False,
                )
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.cache)
        finally:
            if name and Path(name).exists():
                Path(name).unlink()

    async def check_once(self):
        if not self.enabled:
            return
        async with self.lock:
            now = self.clock()
            if self.checked_at is not None and now - self.checked_at < DAY:
                return
            self.checked_at = now
            try:
                # Record an attempt before HTTP so errors and restarts cannot hammer GitHub.
                await asyncio.to_thread(self._save)
            except (OSError, ValueError):
                LOGGER.info("Update check skipped: cannot persist its daily attempt")
                return
            try:
                data = await self.fetch(self.repository)
                tag = data.get("tag_name") if isinstance(data, dict) else None
                self.tag = (
                    tag
                    if isinstance(data, dict)
                    and not data.get("draft")
                    and not data.get("prerelease")
                    and stable_version(tag) is not None
                    else None
                )
                await asyncio.to_thread(self._save)
            except Exception:
                LOGGER.debug(
                    "Release check unavailable; gameplay is unaffected", exc_info=True
                )

    async def run(self):
        while self.enabled:
            await self.check_once()
            remaining = (
                DAY - (self.clock() - self.checked_at)
                if self.checked_at is not None
                else DAY
            )
            await asyncio.sleep(max(1, min(DAY, remaining)))

    def notice(self, build):
        current, latest = stable_version(build.version), stable_version(self.tag)
        prerelease = False
        if (
            current is None
            and isinstance(build.version, str)
            and len(build.version) <= 128
        ):
            installed = BUILD_TAG.fullmatch(build.version)
            if installed:
                current = tuple(map(int, installed.groups()))
                prerelease = True
        if (
            not self.enabled
            or current is None
            or latest is None
            or latest < current
            or (latest == current and not prerelease)
        ):
            return None
        result = {
            "version": "v" + self.tag.removeprefix("v"),
            "release_url": f"https://github.com/{self.repository}/releases/tag/{quote(self.tag, safe='')}",
            "mode": self.hint,
        }
        if (
            self.hint == "deploy"
            and self.command
            and re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", self.tag)
        ):
            result["command"] = self.command + " " + self.tag
        elif self.hint == "compose":
            result["documentation_url"] = (
                f"https://github.com/{self.repository}/blob/main/docs/INSTALL.md#updates"
            )
        return result
