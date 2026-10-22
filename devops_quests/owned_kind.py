"""Verify container identity before bounded node-local training operations."""

import re


def owned_node(runtime, run):
    if not re.fullmatch(r"[a-f0-9]{24}", run["id"]):
        raise ValueError("Invalid owned-node bay")
    name = runtime.cluster + "-control-plane"
    value = runtime.inspect(name)
    marker = runtime.state / "kind-owner"
    expected = runtime.docker(
        "image", "inspect", runtime.kind_image, "--format", "{{.Id}}"
    ).stdout.strip()
    if (
        not value
        or not value["State"]["Running"]
        or not marker.is_file()
        or marker.read_text().strip() != runtime.installation
        or value["Image"] != expected
        or runtime.network not in value["NetworkSettings"]["Networks"]
    ):
        raise RuntimeError("Refusing a foreign training node")
    return name
