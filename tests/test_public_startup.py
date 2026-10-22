import sqlite3
import sys

import pytest

from devops_quests import cli
from devops_quests.store import Store


def test_startup_has_no_automatic_account(tmp_path, monkeypatch, capsys):
    monkeypatch.delenv("DQ_ADMIN_USER", raising=False)
    monkeypatch.delenv("DQ_ADMIN_PASSWORD", raising=False)
    monkeypatch.setattr(
        sys, "argv", ["devops-quests", "serve", "--state", str(tmp_path)]
    )
    seen = {}
    monkeypatch.setattr(cli.web, "run_app", lambda app, **kw: seen.update(kw))
    cli.main()
    with sqlite3.connect(tmp_path / "progress.db") as db:
        assert db.execute("SELECT count(*) FROM users").fetchone()[0] == 0
    assert not (tmp_path / "admin-password").exists()
    assert seen["host"] == "127.0.0.1"
    assert "remote shell inside sandboxes" in capsys.readouterr().out


def test_explicit_first_admin_never_replaces_an_account(tmp_path):
    store = Store(tmp_path / "progress.db")
    assert store.initialize_admin("demo", "long-example-password")
    assert not store.initialize_admin("other", "another-example-password")
    assert store.login("demo", "long-example-password", "fixture")
    assert store.login("demo", "another-example-password", "fixture") is None
    assert not (tmp_path / "admin-password").exists()


def test_first_admin_rejects_invalid_input_without_creating_user(tmp_path):
    store = Store(tmp_path / "progress.db")
    with pytest.raises(ValueError):
        store.initialize_admin("Root Space", "long-example-password")
    with pytest.raises(ValueError):
        store.initialize_admin("demo", "short")
    with store.connect() as db:
        assert db.execute("SELECT count(*) FROM users").fetchone()[0] == 0
