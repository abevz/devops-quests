"""Cold Gitea initialization can outlast a minute on the bounded VM disk."""

import subprocess

from devops_quests.platform import Platform


def test_slow_healthy_gitea_finishes_before_admin_bootstrap(monkeypatch):
    class SlowGitea:
        probes = 0
        admin_created = False

        def exec(self, run, script, **kwargs):
            if "/api/healthz" in script:
                self.probes += 1
                return subprocess.CompletedProcess(
                    [], int(self.probes <= 60), "", "connection refused"
                )
            assert self.admin_created
            return subprocess.CompletedProcess([], 0, "", "")

        def docker(self, *args):
            assert self.probes > 60
            self.admin_created = True

    runtime = SlowGitea()
    platform = Platform(runtime)
    monkeypatch.setattr(platform, "container", lambda *args, **kwargs: "test-gitea")
    monkeypatch.setattr("devops_quests.platform.time.sleep", lambda seconds: None)
    credentials = platform.gitea({"id": "cold-sqlite-fixture"})
    assert runtime.admin_created
    assert credentials["GIT_URL"].endswith("/rail/station.git")
