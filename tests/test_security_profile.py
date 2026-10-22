"""A security fixture must not open the owner's normal progress database."""

import os

import pytest

from scripts.local_security_check import isolated_profile


@pytest.mark.parametrize("alias", ["direct", "descendant", "symlink", "hardlink"])
def test_security_profile_rejects_live_database_aliases_before_store_use(
    tmp_path, alias
):
    state = tmp_path / "runtime"
    state.mkdir()
    normal = state / "progress.db"
    normal.write_bytes(b"owner sentinel")
    fixture = tmp_path / "fixture"
    fixture.mkdir()
    if alias == "direct":
        fixture = state
    elif alias == "descendant":
        fixture = state / "nested"
    elif alias == "symlink":
        (fixture / "progress.db").symlink_to(normal)
    else:
        os.link(normal, fixture / "progress.db")
    with pytest.raises(ValueError, match="synthetic"):
        isolated_profile(fixture, state)
    assert normal.read_bytes() == b"owner sentinel"


def test_separate_fixture_is_accepted_without_creating_a_database(tmp_path):
    fixture = tmp_path / "fixture"
    assert isolated_profile(fixture, tmp_path / "runtime") == fixture
    assert not fixture.exists()
