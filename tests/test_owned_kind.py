"""No node-local operation can use a foreign image, bridge or identity."""

from types import SimpleNamespace

import pytest

from devops_quests.owned_kind import owned_node

RUN = {"id": "a" * 24, "level": 112}


@pytest.mark.parametrize("bad", ["image", "bridge", "marker", "stopped"])
def test_owned_node_rejects_drift_before_mutation(tmp_path, bad):
    (tmp_path / "kind-owner").write_text("foreign" if bad == "marker" else "owner")

    class Runtime:
        state = tmp_path
        installation = "owner"
        network = "internal"
        kind_image = "sha256:pinned"
        cluster = "devops-quests-0123456789"

        def inspect(self, name):
            assert name == self.cluster + "-control-plane"
            return {
                "State": {"Running": bad != "stopped"},
                "Image": "sha256:foreign" if bad == "image" else "sha256:pinned",
                "NetworkSettings": {
                    "Networks": {} if bad == "bridge" else {"internal": {}}
                },
            }

        def docker(self, *args, **kwargs):
            assert args == ("image", "inspect", self.kind_image, "--format", "{{.Id}}")
            return SimpleNamespace(stdout="sha256:pinned")

    with pytest.raises(RuntimeError, match="foreign training node"):
        owned_node(Runtime(), RUN)
