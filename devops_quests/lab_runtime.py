"""Owned, persistent Lab resources. No host socket or host filesystem in the shell."""

import base64
import fcntl
import hashlib
import io
import json
import os
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
from datetime import UTC, datetime

import yaml

from .lab_create import save_record
from .runtime import Runtime


class LabRuntime(Runtime):
    def __init__(self, state, root, lab, profile):
        if not re.fullmatch(r"[a-f0-9]{24}", lab["id"]):
            raise ValueError("Invalid lab identity")
        super().__init__(state / "labs" / lab["id"], root)
        saved = self.state / "runtime.json"
        if saved.exists():
            config = json.loads(saved.read_text())
            self.profile = config["profile"]
            self.image, self.kind_image, self.images = (
                config["image"],
                config["kind_image"],
                config["images"],
            )
        else:
            self.profile = profile
            if lab["profile"] == "kubernetes":
                self.images.update(
                    json.loads((self.root / "labs/images.lock.json").read_text())
                )
            save_record(
                saved,
                {
                    "profile": profile,
                    "image": self.image,
                    "kind_image": self.kind_image,
                    "images": self.images,
                },
            )
        self.cluster = "dq-lab-" + self.installation
        self.journal = self.state / "nodes.json"
        self.creation = self.state / "creation.json"

    def settle_creation(self):
        """Wait for the recorded creator, then journal only its private nodes."""
        if not self.creation.exists():
            return
        with self.creation.with_suffix(".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            record = json.loads(self.creation.read_text())
            if self.journal.exists():
                return
            # A delayed worker must never start after recovery has freed the slot.
            record["status"] = "settled"
            save_record(self.creation, record)
            network = self.docker("network", "inspect", self.network, check=False)
            info = json.loads(network.stdout)[0] if network.returncode == 0 else {}
            if (
                info.get("Id") != record["network_id"]
                or info.get("Labels", {}).get("devops-quests.installation")
                != self.installation
            ):
                raise RuntimeError("Cannot verify the Lab creation network")
            created = {}
            for name in self.node_names():
                obj = self.inspect(name)
                if not obj:
                    continue
                endpoints = obj["NetworkSettings"]["Networks"]
                if (
                    obj["Config"]["Image"] != self.kind_image
                    or obj["Config"].get("Labels", {}).get("io.x-k8s.kind.cluster")
                    != self.cluster
                    or set(endpoints) != {self.network}
                    or endpoints[self.network].get("NetworkID") != record["network_id"]
                    or datetime.fromisoformat(obj["Created"])
                    < datetime.fromisoformat(record["started"])
                ):
                    raise RuntimeError("Cannot verify a partially created Lab node")
                created[name] = obj["Id"]
            save_record(self.journal, created)

    def dependencies(self, run):
        # Kubernetes is prepared separately, with its own administrator identity.
        return set(self.profile["services"]) - {"kubernetes"}

    def owned(self, name):
        if not super().owned(name):
            return False
        ready = self.state / "ready"
        return (
            not ready.exists()
            or self.inspect(name)["Id"] in json.loads(ready.read_text())["containers"]
        )

    def node_names(self):
        return [self.cluster + "-control-plane"] + [
            self.cluster + ("-worker" if i == 0 else "-worker" + str(i + 1))
            for i in range(self.profile.get("workers", 0))
        ]

    def nodes(self, allow_missing=False):
        expected = json.loads(self.journal.read_text()) if self.journal.exists() else {}
        result = []
        for name in self.node_names():
            obj = self.inspect(name)
            if obj:
                networks = set(obj["NetworkSettings"]["Networks"])
                # An interrupted initial IP pin can leave an exact journaled
                # node disconnected. It is still safe to stop/delete that ID.
                allowed_networks = networks == {self.network} or (
                    not networks and not (self.state / "ready").exists()
                )
                if (
                    obj["Id"] != expected.get(name)
                    or obj["Config"]["Image"] != self.kind_image
                    or obj["Config"].get("Labels", {}).get("io.x-k8s.kind.cluster")
                    != self.cluster
                    or not allowed_networks
                ):
                    raise RuntimeError("Cannot verify the saved Lab node identity")
                result.append(obj)
            elif name in expected and not allow_missing:
                raise RuntimeError(
                    "A saved Lab node is missing; explicit reset is required"
                )
        return result

    def containers(self, allow_missing=False):
        ids = self.docker("ps", "-aq", "--filter", "label=" + self.label).stdout.split()
        objects = []
        for identifier in ids:
            obj = self.inspect(identifier)
            if not obj or not self.owned(identifier):
                raise RuntimeError("Cannot verify Lab container ownership")
            objects.append(obj)
        return objects + self.nodes(allow_missing)

    def docker(self, *args, **kwargs):
        if args and args[0] == "run" and args[-1] == self.image and "--cpus" in args:
            args = list(args)
            args[args.index("--cpus") + 1] = "0.5"
        # The game target entrypoint restores a quest fixture at boot. Lab SSH
        # targets instead keep their writable layer across stop/resume.
        if args and args[0] == "run" and args[-1] == "target":
            script = """set -eu
ssh-keygen -A
mkdir -p /root/.ssh /srv/site
chmod 700 /root/.ssh
cp /run/dq/authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
test -e /srv/site/message || printf 'unconfigured\\n' > /srv/site/message
dq-service start
exec /usr/sbin/sshd -D -e -p 2222 -o PasswordAuthentication=no -o PermitRootLogin=prohibit-password -o UsePAM=no
"""
            args = (*args[:-1], "/bin/bash", "-c", script)
        return super().docker(*args, **kwargs)

    def load_image(self, key, node=None):
        for name in [node] if node else self.node_names():
            obj = next(obj for obj in self.nodes() if obj["Name"] == "/" + name)
            cpus = obj["HostConfig"]["NanoCpus"] / 1_000_000_000
            # Image unpacking is bounded by the installation's shared CPU
            # slice too. Let a preparing worker use spare capacity, then
            # restore its normal limit even when an import fails.
            try:
                self.docker("update", "--cpus", str(max(cpus, 1.0)), obj["Id"])
                super().load_image(key, node=name, timeout=600)
            finally:
                self.docker("update", "--cpus", str(cpus), obj["Id"])

    def prepare_cluster(self):
        self.ensure_network()
        if any(self.inspect(name) for name in self.node_names()):
            raise RuntimeError("The Lab cluster name is already in use")
        config = self.state / "kind.yaml"
        config.write_text(
            yaml.safe_dump(
                {
                    "kind": "Cluster",
                    "apiVersion": "kind.x-k8s.io/v1alpha4",
                    "networking": {"apiServerAddress": "127.0.0.1"},
                    "nodes": [{"role": "control-plane"}]
                    + [
                        {"role": "worker"}
                        for _ in range(self.profile.get("workers", 0))
                    ],
                }
            )
        )
        network = json.loads(self.docker("network", "inspect", self.network).stdout)[0]
        token = secrets.token_hex(16)
        save_record(
            self.creation,
            {
                "status": "pending",
                "token": token,
                "started": datetime.now(UTC).isoformat(),
                "network_id": network["Id"],
                "command": [
                    str(self.root / "bin/kind"),
                    "create",
                    "cluster",
                    "--retain",
                    "--name",
                    self.cluster,
                    "--kubeconfig",
                    str(self.kubeconfig),
                    "--config",
                    str(config),
                    "--image",
                    self.kind_image,
                    "--wait",
                    "180s",
                ],
                "environment": {
                    "DOCKER_HOST": "unix:///var/run/docker.sock",
                    "KIND_EXPERIMENTAL_DOCKER_NETWORK": self.network,
                },
            },
        )
        # The small worker owns the creation lock until kind exits (bounded by
        # its own timeout). A backend SIGKILL leaves that worker able to finish;
        # recovery waits for it before releasing the global compute slot.
        with (self.state / "kind-create.log").open("a") as log:
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "devops_quests.lab_create",
                    str(self.creation),
                    token,
                ],
                cwd=self.root,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                check=False,
            )
        self.settle_creation()
        creation = json.loads(self.creation.read_text())
        if creation.get("returncode") != 0:
            missing_port = "failed to get api server port" in (
                self.state / "kind-create.log"
            ).read_text()
            if creation.get("returncode") != 1 or not missing_port:
                raise RuntimeError("Lab cluster creation failed; inspect kind-create.log")
        # kind may report a missing published API port on our internal bridge.
        # Validate the actual nodes and private API below; no host port is needed.
        nodes = self.nodes()
        if len(nodes) != len(self.node_names()):
            raise RuntimeError("Lab cluster preparation did not complete")
        # An internal bridge deliberately exposes no host port. Extract only
        # this cluster's admin config, using its container IP as the endpoint.
        cp = nodes[0]
        config = yaml.safe_load(
            self.docker("exec", cp["Id"], "cat", "/etc/kubernetes/admin.conf").stdout
        )
        config["clusters"][0]["cluster"]["server"] = (
            "https://"
            + cp["NetworkSettings"]["Networks"][self.network]["IPAddress"]
            + ":6443"
        )
        config["contexts"][0]["name"] = "kind-" + self.cluster
        config["current-context"] = "kind-" + self.cluster
        self.kubeconfig.write_text(yaml.safe_dump(config))
        self.kubeconfig.chmod(0o600)
        for obj in nodes:
            control = obj["Name"].endswith("-control-plane")
            memory = self.profile.get("control_memory", "2g") if control else "1g"
            self.docker(
                "update",
                "--memory",
                memory,
                "--memory-swap",
                memory,
                "--cpus",
                "1.5" if control else "0.5",
                obj["Id"],
            )
        self.wait_cluster()
        self.load_image("app")
        if self.profile.get("workers"):
            self.load_image("lab_nginx")
            self.load_image("lab_tools")
            self.load_diagnostic_image()

    def load_diagnostic_image(self):
        asset = json.loads((self.root / ".state/lab-images.json").read_text())[
            "diagnostic"
        ]
        found = self.docker(
            "image", "inspect", asset["tag"], "--format={{.Id}}"
        ).stdout.strip()
        if found != asset["id"]:
            raise RuntimeError("The diagnostic image identity changed")
        subprocess.run(
            [
                str(self.root / "bin/kind"),
                "load",
                "docker-image",
                asset["tag"],
                "--name",
                self.cluster,
            ],
            env=dict(os.environ, DOCKER_HOST="unix:///var/run/docker.sock"),
            check=True,
            capture_output=True,
            timeout=180,
        )

    def wait_cluster(self):
        for _ in range(90):
            if (
                self.kube(
                    "get", "--raw=/readyz", "--request-timeout=2s", check=False
                ).returncode
                == 0
            ):
                break
            time.sleep(1)
        else:
            raise RuntimeError("The saved Lab API did not become ready")
        self.kube(
            "wait",
            "--for=condition=Ready",
            "node",
            "--all",
            "--timeout=120s",
            timeout=150,
        )

    def start(self, lab):
        run = dict(lab, level=0)
        ready = self.state / "ready"
        if ready.exists():
            objects = self.containers()
            if (
                sorted(obj["Id"] for obj in objects)
                != json.loads(ready.read_text())["containers"]
            ):
                raise RuntimeError("A saved Lab resource is missing or replaced")
            if not self.owned(self.names(lab)["workstation"]):
                raise RuntimeError("The saved Lab workstation is missing")
            self.ensure_network()
            for obj in objects:
                if not obj["State"]["Running"]:
                    self.docker("start", obj["Id"])
            if "kubernetes" in self.profile["services"]:
                self.wait_cluster()
            self.exec(run, "test -d ~/lab/examples")
            if "tofu" in self.profile["services"]:
                for _ in range(45):
                    if (
                        self.exec(
                            run, "docker info >/dev/null 2>&1", check=False
                        ).returncode
                        == 0
                    ):
                        break
                    time.sleep(1)
                else:
                    raise RuntimeError("Saved Docker daemon did not restart")
            return
        if (self.state / "started").exists():
            raise RuntimeError(
                "Partial Lab preparation is retained; use explicit reset"
            )
        (self.state / "started").touch()
        if "kubernetes" in self.profile["services"]:
            self.prepare_cluster()
            self.kube("create", "namespace", self.namespace(lab))
        super().create(run)
        if "kubernetes" in self.profile["services"]:
            client = self.state / "bays" / lab["id"] / "client/kubeconfig"
            client.write_text(self.kubeconfig.read_text())
            client.chmod(0o644)
        self.install_examples(run)
        self.pin_addresses()
        if "kubernetes" in self.profile["services"]:
            self.wait_cluster()
        save_record(
            ready,
            {
                "version": lab["version"],
                "containers": sorted(obj["Id"] for obj in self.containers()),
            },
        )

    def pin_addresses(self):
        """Docker's dynamic leases change after stop; Kubernetes embeds node IPs."""
        for obj in self.containers():
            endpoint = obj["NetworkSettings"]["Networks"][self.network]
            address = endpoint["IPAddress"]
            if (endpoint.get("IPAMConfig") or {}).get("IPv4Address") == address:
                continue
            aliases = endpoint.get("Aliases") or []
            self.docker("network", "disconnect", self.network, obj["Id"])
            self.docker(
                "network",
                "connect",
                "--ip",
                address,
                *(arg for alias in aliases for arg in ("--alias", alias)),
                self.network,
                obj["Id"],
            )

    def install_examples(self, run):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w:gz") as archive:
            if run["profile"] == "ansible":
                assets = json.loads(
                    (self.root / "labs/collections.lock.json").read_text()
                )
                for name, asset in assets.items():
                    path = self.root / ".state" / name
                    if hashlib.sha256(path.read_bytes()).hexdigest() != asset["sha256"]:
                        raise RuntimeError(
                            "Collection checksum mismatch; run make lab-assets"
                        )
                    archive.add(path, arcname="full-reuse/vendor/" + name)
            for path in sorted(
                (self.root / "labs/examples" / run["profile"]).rglob("*")
            ):
                if path.is_file():
                    archive.add(
                        path,
                        arcname=str(
                            path.relative_to(
                                self.root / "labs/examples" / run["profile"]
                            )
                        ),
                    )
        encoded = base64.b64encode(stream.getvalue()).decode()
        self.exec(
            run,
            "mkdir -p ~/lab/examples\nprintf %s "
            + shlex.quote(encoded)
            + " | base64 -d | tar -xz -C ~/lab/examples\ncp -a ~/quest/. ~/lab/\nprintf '\\ncd ~/lab\\n' >> ~/.bashrc\n",
        )
        if "argocd" in self.profile["services"]:
            from .platform import Platform

            self.exec(
                run,
                "printf '\\nexport ARGO_NAMESPACE=%s\\nexport LAB_NAMESPACE=%s\\n' "
                + shlex.quote(Platform(self).namespace(run))
                + " "
                + shlex.quote(self.namespace(run))
                + " >> ~/lab/platform.env",
            )
        if run["profile"] == "kubernetes":
            diagnostic = json.loads((self.root / ".state/lab-images.json").read_text())[
                "diagnostic"
            ]["tag"]
            self.exec(
                run,
                "cat > ~/lab/images.env <<'LAB_IMAGES'\n"
                + "\n".join(
                    "export " + key + "=" + shlex.quote(value)
                    for key, value in {
                        "TOOLS": self.images["lab_tools"],
                        "NGINX": self.images["lab_nginx"],
                        "DIAGNOSTIC": diagnostic,
                    }.items()
                )
                + "\nLAB_IMAGES\n",
            )

    def stop(self, lab):
        self.settle_creation()
        objects = self.containers(allow_missing=True)
        for obj in objects:
            if obj["State"]["Running"]:
                self.docker("stop", "--time", "15", obj["Id"], timeout=60)
        if any(obj["State"]["Running"] for obj in self.containers(allow_missing=True)):
            raise RuntimeError("Lab resources are still running")

    def delete(self, lab):
        self.settle_creation()
        objects = self.containers(allow_missing=True)
        for obj in objects:
            self.docker("rm", "-fv", obj["Id"], timeout=90)
        # Retire creation before its journal/network disappear. A restart in
        # the remaining deletion steps can safely observe an empty workspace.
        self.creation.unlink(missing_ok=True)
        self.journal.unlink(missing_ok=True)
        for identifier in self.docker(
            "volume", "ls", "-q", "--filter", "label=" + self.label
        ).stdout.split():
            obj = json.loads(self.docker("volume", "inspect", identifier).stdout)[0]
            if (
                obj.get("Labels", {}).get("devops-quests.installation")
                != self.installation
            ):
                raise RuntimeError("Refusing a foreign volume")
            self.docker("volume", "rm", identifier)
        network = self.docker("network", "inspect", self.network, check=False)
        if network.returncode == 0:
            if (
                json.loads(network.stdout)[0]
                .get("Labels", {})
                .get("devops-quests.installation")
                != self.installation
            ):
                raise RuntimeError("Refusing a foreign network")
            self.firewall(remove=True)
            self.docker("network", "rm", self.network)
        # Preserve the installation identity across an explicit reset.
        for path in self.state.iterdir():
            if path.name in {"installation", "runtime.json"}:
                continue
            if path.is_symlink() or path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
