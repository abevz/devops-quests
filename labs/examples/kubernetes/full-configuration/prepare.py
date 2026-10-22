import json
import os
import pathlib
import subprocess

import yaml

root = pathlib.Path(__file__).resolve().parent
ns = "lab-full-configuration"
node = json.loads(
    subprocess.run(
        ["kubectl", "get", "nodes", "-o", "json"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
)
worker = next(
    n["metadata"]["name"]
    for n in node["items"]
    if n["metadata"]["name"].endswith("-worker")
)


def adapt(obj):
    if isinstance(obj, dict):
        for key, value in list(obj.items()):
            if key == "image":
                if value.startswith("nginx:"):
                    obj[key] = os.environ["NGINX"]
                elif value.startswith("busybox:"):
                    obj[key] = os.environ["DQ_APP_IMAGE"]
                elif value == "vg-k8s-app:1":
                    obj[key] = os.environ["DIAGNOSTIC"]
                obj["imagePullPolicy"] = "Never"
            elif key == "namespace" and value == "vg-k8s":
                obj[key] = ns
            elif key == "kubernetes.io/hostname" and value == "vg-k8s-worker":
                obj[key] = worker
            else:
                adapt(value)
    elif isinstance(obj, list):
        for item in obj:
            adapt(item)


for source in root.glob("source-*.yaml"):
    docs = list(yaml.safe_load_all(source.read_text()))
    for obj in docs:
        adapt(obj)
        if obj["kind"] == "Namespace":
            obj["metadata"]["name"] = ns
    (root / source.name.replace("source-", "lab-")).write_text(yaml.safe_dump_all(docs))
