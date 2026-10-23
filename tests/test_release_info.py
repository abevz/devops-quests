"""Authenticated build identity and opt-in, rate-limited release notices."""

import asyncio
import json

import pytest

from devops_quests.release_info import BuildInfo, UpdateChecker, stable_version


def test_installed_manifest_takes_precedence(tmp_path):
    (tmp_path / "RELEASE.json").write_text(
        json.dumps({"version": "v1.0.0", "commit": "09d5c7a" + "0" * 33})
    )
    assert BuildInfo.read(tmp_path).payload() == {
        "version": "v1.0.0",
        "commit": "09d5c7a",
    }


def test_installed_prerelease_identity_is_preserved_but_never_offered(tmp_path):
    (tmp_path / "RELEASE.json").write_text(
        json.dumps({"version": "v1.2.0-rc.1+build.3", "commit": "abcdef0" + "1" * 33})
    )
    build = BuildInfo.read(tmp_path)
    assert build.payload() == {"version": "v1.2.0-rc.1+build.3", "commit": "abcdef0"}
    assert stable_version(build.version) is None


@pytest.mark.parametrize(
    ("installed", "offered"),
    [
        ("v1.2.0-rc.1", True),
        ("v1.3.0-rc.1", False),
        ("v1.2.0", False),
        ("v1.1.0", True),
    ],
)
def test_stable_release_can_replace_its_installed_release_candidate(
    tmp_path, installed, offered
):
    checker = UpdateChecker(tmp_path, enabled=True)
    checker.tag = "v1.2.0"
    assert bool(checker.notice(BuildInfo(installed, "abcdef0"))) is offered


def test_source_package_without_git_is_identified_as_dev(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "devops_quests.release_info.metadata.version", lambda _: "1.1.0"
    )
    assert BuildInfo.read(tmp_path).payload() == {"version": "v1.1.0", "commit": "dev"}


@pytest.mark.parametrize(
    "tag", ["v1.1.0-rc.1", "1.2", "v01.2.3", "v1.2.3+bad..meta", "<script>", None]
)
def test_non_stable_or_invalid_versions_are_not_candidates(tag):
    assert stable_version(tag) is None


def test_semver_order_ignores_build_metadata():
    assert stable_version("v1.10.0") > stable_version("1.9.99")
    assert stable_version("v1.2.3+build.4") == stable_version("v1.2.3")


@pytest.mark.asyncio
async def test_disabled_means_no_fetch_or_cache_write(tmp_path):
    calls = []

    async def fetch(repo):
        calls.append(repo)
        raise AssertionError("Outbound request while disabled")

    checker = UpdateChecker(tmp_path, fetch=fetch)
    await checker.check_once()
    await checker.run()
    assert calls == [] and list(tmp_path.iterdir()) == []
    assert checker.notice(BuildInfo("v1.0.0", "abc1234")) is None


@pytest.mark.asyncio
async def test_daily_attempt_cache_survives_restart_and_concurrent_calls(tmp_path):
    clock = [100000.0]
    calls = []

    async def fetch(repo):
        calls.append(repo)
        await asyncio.sleep(0)
        return {"tag_name": "v1.10.0", "draft": False, "prerelease": False}

    def make():
        return UpdateChecker(
            tmp_path, enabled=True, hint="deploy", fetch=fetch, clock=lambda: clock[0]
        )

    first = make()
    await asyncio.gather(first.check_once(), first.check_once())
    assert calls == ["abevz/devops-quests"]
    assert (
        first.notice(BuildInfo("v1.9.0", "abc1234"))["command"]
        == "sudo /opt/devops-quests/operator/deploy.sh v1.10.0"
    )
    restarted = make()
    await restarted.check_once()
    assert len(calls) == 1
    clock[0] += 86400
    await restarted.check_once()
    assert len(calls) == 2
    assert restarted.notice(BuildInfo("v1.10.0+local.2", "abc1234")) is None


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "payload",
    [
        {"tag_name": "v9.0.0", "prerelease": True},
        {"tag_name": "v9.0.0-rc.1", "prerelease": False},
        {"tag_name": "v9.0.0", "draft": True},
        {"tag_name": "not-a-version"},
    ],
)
async def test_draft_and_prerelease_data_are_ignored(tmp_path, payload):
    async def fetch(_):
        return payload

    checker = UpdateChecker(tmp_path, enabled=True, fetch=fetch)
    await checker.check_once()
    assert checker.notice(BuildInfo("v1.0.0", "abc1234")) is None


@pytest.mark.asyncio
async def test_network_error_is_silent_and_cached(tmp_path):
    calls = []

    async def fetch(repo):
        calls.append(repo)
        raise TimeoutError("fixture timeout")

    checker = UpdateChecker(tmp_path, enabled=True, fetch=fetch)
    await checker.check_once()
    await checker.check_once()
    restarted = UpdateChecker(tmp_path, enabled=True, fetch=fetch)
    await restarted.check_once()
    assert len(calls) == 1
    assert restarted.notice(BuildInfo("v1.0.0", "abc1234")) is None


@pytest.mark.asyncio
async def test_repository_override_and_explicit_hint(tmp_path):
    calls = []

    async def fetch(repo):
        calls.append(repo)
        return {"tag_name": "v2.0.0", "html_url": "https://untrusted.invalid/"}

    checker = UpdateChecker(
        tmp_path, enabled=True, repository="example/fork", hint="compose", fetch=fetch
    )
    await checker.check_once()
    notice = checker.notice(BuildInfo("v1.0.0", "abc1234"))
    assert calls == ["example/fork"]
    assert (
        notice["release_url"] == "https://github.com/example/fork/releases/tag/v2.0.0"
    )
    assert (
        notice["documentation_url"]
        == "https://github.com/example/fork/blob/main/docs/INSTALL.md#updates"
    )
    assert "command" not in notice


@pytest.mark.asyncio
async def test_invalid_repository_does_not_send_requests(tmp_path):
    async def fetch(_):
        raise AssertionError("SSRF-shaped repository setting must be disabled")

    checker = UpdateChecker(
        tmp_path, enabled=True, repository="https://untrusted.invalid/", fetch=fetch
    )
    await checker.check_once()
    assert checker.notice(BuildInfo("v1.0.0", "abc1234")) is None


@pytest.mark.asyncio
async def test_github_transport_handles_chunked_json_with_timeout_and_no_credentials(
    monkeypatch,
):
    from devops_quests.release_info import fetch_latest

    observed = {}

    class Content:
        async def iter_chunked(self, size):
            assert size == 65536
            for chunk in (b'{"tag_', b'name":"v1.', b'1.0"}'):
                yield chunk

    class Response:
        status = 200
        content = Content()

        def raise_for_status(self):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            observed["response_closed"] = True

    class Session:
        def __init__(self, **kwargs):
            observed.update(kwargs)

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            observed["session_closed"] = True

        def get(self, url, **kwargs):
            observed["url"] = url
            observed.update(kwargs)
            return Response()

    monkeypatch.setattr("devops_quests.release_info.aiohttp.ClientSession", Session)
    assert await fetch_latest("example/fork") == {"tag_name": "v1.1.0"}
    assert (
        observed["url"] == "https://api.github.com/repos/example/fork/releases/latest"
    )
    assert observed["timeout"].total == 5
    assert observed["allow_redirects"] is False
    assert "Authorization" not in observed["headers"]
    assert observed["response_closed"] and observed["session_closed"]
