"""Docker resources are created and removed only inside this installation's scope."""

import base64
import functools
import json
import operator
import os
import re
import shlex
import shutil
import subprocess
import threading
import time
import uuid
from pathlib import Path

from .catalog import ROOT
from .oci import verified_config

DOCKER = ("docker", "--host", "unix:///var/run/docker.sock")
CLUSTER = "devops-quests"


class Runtime:
    def __init__(self, state, root=ROOT):
        self.state = Path(state).resolve()
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.root = Path(root)
        identity = self.state / "installation"
        if not identity.exists():
            temporary = identity.with_suffix(".tmp")
            temporary.write_text(uuid.uuid4().hex[:10])
            temporary.chmod(0o600)
            temporary.replace(identity)
        self.installation = identity.read_text().strip()
        if not re.fullmatch(r"[a-f0-9]{10}", self.installation):
            raise RuntimeError(
                "Invalid installation identity; no resources were changed."
            )
        # New installations must coexist with another checkout on the same host.
        # Keep the fixed name for states created before names were recorded.
        cluster_record = self.state / "kind-cluster-name"
        scoped_cluster = CLUSTER + "-" + self.installation
        if cluster_record.exists():
            self.cluster = cluster_record.read_text().strip()
        else:
            legacy = any(
                (self.state / name).exists()
                for name in (
                    "kind-owner",
                    "kind-node-id",
                    "kind-admin.yaml",
                    "kind.yaml",
                )
            )
            self.cluster = CLUSTER if legacy else scoped_cluster
            temporary = cluster_record.with_suffix(".tmp")
            temporary.write_text(self.cluster)
            temporary.chmod(0o600)
            temporary.replace(cluster_record)
        if self.cluster not in {CLUSTER, scoped_cluster}:
            raise RuntimeError(
                "Invalid installation cluster name; no resources were changed."
            )
        self.network = "devops-quests-" + self.installation
        self.bridge = "dq-" + self.installation
        self.label = "devops-quests.installation=" + self.installation
        self.images = json.loads((self.root / "images.lock.json").read_text())
        host_images = self.root / ".state/host-images.json"
        if host_images.exists():
            overrides = json.loads(host_images.read_text())
            if (
                not isinstance(overrides, dict)
                or not set(overrides) <= {"dind", "gitea", "vault", "registry"}
                or any(
                    not isinstance(value, str)
                    or not re.fullmatch(r"sha256:[a-f0-9]{64}", value)
                    for value in overrides.values()
                )
            ):
                raise RuntimeError("Invalid release host-image identities")
            self.images.update(overrides)
        built = self.root / ".state" / "built-image.json"
        self.image = json.loads(built.read_text())["id"] if built.exists() else None
        kind_built = self.root / ".state/kind-image.json"
        self.kind_image = (
            json.loads(kind_built.read_text())["id"]
            if kind_built.exists()
            else self.images["kind"]
        )
        self.lock = threading.RLock()
        self.kubeconfig = self.state / "kind-admin.yaml"
        import yaml

        self.levels = {
            x["id"]: x for x in yaml.safe_load((self.root / "levels.yaml").read_text())
        }

    def dependencies(self, run):
        return set(self.levels[run["level"]]["dependencies"])

    @staticmethod
    def command(args, *, input=None, timeout=120, check=True):
        result = subprocess.run(
            list(args),
            input=input,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        if check and result.returncode:
            raise RuntimeError(result.stderr[-3000:] or result.stdout[-3000:])
        return result

    def docker(self, *args, **kwargs):
        return self.command((*DOCKER, *args), **kwargs)

    def labels(self):
        return ["--label", "devops-quests=true", "--label", self.label]

    def inspect(self, name):
        data = self.docker("inspect", name, check=False)
        return json.loads(data.stdout)[0] if data.returncode == 0 else None

    def owned(self, name):
        data = self.inspect(name)
        return (
            data
            and data.get("Config", {})
            .get("Labels", {})
            .get("devops-quests.installation")
            == self.installation
        )

    def remove_container(self, name):
        if self.inspect(name) and not self.owned(name):
            raise RuntimeError(f"Refusing foreign container {name}")
        if self.owned(name):
            self.docker("rm", "-f", name)

    def exec(self, run, script, *, root=False, check=True, timeout=120):
        name = self.names(run)["workstation"]
        if not self.owned(name):
            raise RuntimeError("This bay is unavailable.")
        return self.docker(
            "exec",
            "-i",
            "--user",
            "0" if root else "1000:1000",
            "--env",
            "BASH_ENV=/dev/null",
            "--env",
            "KUBECONFIG=/run/dq/kubeconfig",
            "--env",
            "DQ_NAMESPACE=" + self.namespace(run),
            "--env",
            "DQ_NODE_NAME=" + self.cluster + "-control-plane",
            "--env",
            "DQ_APP_IMAGE=" + self.images["app"],
            name,
            "/bin/bash",
            "--noprofile",
            "--norc",
            "-s",
            input=script,
            check=check,
            timeout=timeout,
        )

    def names(self, run):
        base = "dq-" + self.installation + "-" + run["id"][:12]
        return {
            "workstation": base + "-ws",
            "dind": base + "-docker",
            "app1": base + "-a",
            "app2": base + "-b",
            "app3": base + "-c",
        }

    @staticmethod
    def namespace(run):
        return "dq-" + run["id"]

    def kube(self, *args, **kwargs):
        return self.command(
            (
                str(self.root / "bin" / "kubectl"),
                "--kubeconfig",
                str(self.kubeconfig),
                "--context",
                "kind-" + self.cluster,
                *args,
            ),
            **kwargs,
        )

    def firewall(self, remove=False):
        # Only our bridge matches these hooks. No flush or broad FORWARD changes.
        chain = "DQ" + self.installation.upper()
        script = "set -eu\n"
        for table_chain, suffix in (("INPUT", "I"), ("FORWARD", "F")):
            own = chain + suffix
            hook = f"{table_chain} -i {self.bridge} -m comment --comment devops-quests-{self.installation} -j {own}"
            if remove:
                script += f"iptables -C {hook} 2>/dev/null && iptables -D {hook} || true\niptables -F {own} 2>/dev/null || true\niptables -X {own} 2>/dev/null || true\n"
            else:
                script += f"iptables -N {own} 2>/dev/null || true\n"
                script += f"iptables -C {own} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || iptables -A {own} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN\n"
                if suffix == "F":
                    script += f"iptables -C {own} -o {self.bridge} -j RETURN 2>/dev/null || iptables -A {own} -o {self.bridge} -j RETURN\n"
                script += f"iptables -C {own} -j DROP 2>/dev/null || iptables -A {own} -j DROP\n"
                script += f"iptables -C {hook} 2>/dev/null || iptables -I {hook}\n"
        self.docker(
            "run",
            "--rm",
            *self.labels(),
            "--network",
            "host",
            "--cap-drop",
            "ALL",
            "--cap-add",
            "NET_ADMIN",
            "--entrypoint",
            "/bin/sh",
            self.image,
            "-c",
            script,
        )

    def ensure_network(self):
        if not self.image:
            raise RuntimeError("Run make bootstrap first.")
        with self.lock:
            network = self.docker("network", "inspect", self.network, check=False)
            if network.returncode:
                self.docker(
                    "network",
                    "create",
                    "--internal",
                    *self.labels(),
                    "--opt",
                    "com.docker.network.bridge.name=" + self.bridge,
                    self.network,
                )
            else:
                obj = json.loads(network.stdout)[0]
                if (
                    obj.get("Labels", {}).get("devops-quests.installation")
                    != self.installation
                    or not obj["Internal"]
                ):
                    raise RuntimeError("Refusing a foreign or external network.")
            self.firewall()

    def ensure_cluster(self):
        with self.lock:
            self.ensure_network()
            node = self.inspect(self.cluster + "-control-plane")
            marker = self.state / "kind-owner"
            if node:
                if not marker.exists() or marker.read_text() != self.installation:
                    raise RuntimeError("A foreign kind cluster uses the reserved name.")
                if not self.kubeconfig.exists():
                    raise RuntimeError(
                        "Owned kind initialization was interrupted; run make reset before retrying."
                    )
                if not node["State"]["Running"]:
                    self.docker("start", self.cluster + "-control-plane")
                    for _ in range(90):
                        if (
                            self.kube(
                                "get",
                                "--raw=/readyz",
                                "--request-timeout=2s",
                                check=False,
                            ).returncode
                            == 0
                        ):
                            break
                        time.sleep(1)
                    else:
                        raise RuntimeError("The owned kind API did not restart.")
                    self.kube(
                        "wait",
                        "--for=condition=Ready",
                        "node",
                        "--all",
                        "--timeout=120s",
                        timeout=150,
                    )
                self.load_image("app")
                return
            config = self.state / "kind.yaml"
            config.write_text("""kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: 127.0.0.1
nodes:
- role: control-plane
""")
            env = dict(
                os.environ,
                DOCKER_HOST="unix:///var/run/docker.sock",
                KIND_EXPERIMENTAL_DOCKER_NETWORK=self.network,
            )
            result = subprocess.run(
                [
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
                env=env,
                capture_output=True,
                text=True,
                timeout=300,
                check=False,
            )
            # Record ownership only for the exact newly requested cluster/network.
            node = self.inspect(self.cluster + "-control-plane")
            if node and self.network in node["NetworkSettings"]["Networks"]:
                marker.write_text(self.installation)
                (self.state / "kind-node-id").write_text(node["Id"])
            if result.returncode:
                # Docker internal networks deliberately have no published ports.
                # kind completed kubeadm but cannot export a loopback port on
                # Docker 29. Read our node's admin config, then prove readiness.
                if (
                    not node
                    or not node["State"]["Running"]
                    or "failed to get api server port" not in result.stderr
                ):
                    raise RuntimeError(result.stderr[-3000:])
                import yaml

                config = yaml.safe_load(
                    self.docker(
                        "exec",
                        self.cluster + "-control-plane",
                        "cat",
                        "/etc/kubernetes/admin.conf",
                    ).stdout
                )
                config["clusters"][0]["cluster"]["server"] = (
                    "https://"
                    + node["NetworkSettings"]["Networks"][self.network]["IPAddress"]
                    + ":6443"
                )
                config["contexts"][0]["name"] = "kind-" + self.cluster
                config["current-context"] = "kind-" + self.cluster
                self.kubeconfig.write_text(yaml.safe_dump(config))
                self.kube(
                    "wait",
                    "--for=condition=Ready",
                    "node",
                    "--all",
                    "--timeout=120s",
                    timeout=150,
                )
            self.kubeconfig.chmod(0o600)
            self.docker(
                "update",
                "--memory",
                "3g",
                "--memory-swap",
                "3g",
                "--cpus",
                "2",
                self.cluster + "-control-plane",
            )
            # Preload pinned workloads; the game network has no Internet route.
            self.load_image("app")

    def load_image(self, key, node=None, timeout=180):
        node = node or self.cluster + "-control-plane"
        archive = self.root / ".state" / (key + "-oci.tar")
        if not archive.is_file():
            raise RuntimeError("Run make bootstrap to prepare immutable OCI archives.")
        pinned_manifest = self.images[key].split("@", 1)[1]
        expected_config = verified_config(archive, pinned_manifest)
        # Import the original manifest digest and reference, not a digest-less
        # Docker save archive. CRI must resolve image@sha256 with Never policy.
        with archive.open("rb") as source:
            result = subprocess.run(
                [
                    *DOCKER,
                    "exec",
                    "-i",
                    node,
                    "ctr",
                    "--namespace",
                    "k8s.io",
                    "images",
                    "import",
                    "--local",
                    "--base-name",
                    self.images[key].split("@", 1)[0].rsplit(":", 1)[0],
                    "--label",
                    "io.cri-containerd.image=managed",
                    "-",
                ],
                stdin=source,
                capture_output=True,
                timeout=timeout,
                check=False,
            )
        if result.returncode:
            raise RuntimeError(result.stderr.decode()[-3000:])
        # crane historically canonicalized Docker Hub to index.docker.io, while
        # CRI resolves docker.io. Both names identify the same verified manifest.
        reference = self.images[key]
        repository = reference.split("@", 1)[0].rsplit(":", 1)[0]
        canonical = repository + "@" + reference.split("@", 1)[1]
        imported = self.docker(
            "exec",
            node,
            "ctr",
            "--namespace",
            "k8s.io",
            "images",
            "ls",
            "-q",
        ).stdout.split()
        if canonical not in imported:
            alias = canonical.replace("docker.io/", "index.docker.io/", 1)
            if alias not in imported:
                raise RuntimeError("Pinned image reference missing after import")
            self.docker(
                "exec",
                node,
                "ctr",
                "--namespace",
                "k8s.io",
                "images",
                "tag",
                alias,
                canonical,
            )
        # Canonicalize legacy unnamed OCI aliases from the kind image and old
        # imports. Containerd checkpoint lookup normalizes these names to
        # docker.io/library; the corresponding metadata key must actually exist.
        for name in imported:
            if name.startswith("import-") and "/" not in name:
                full = "docker.io/library/" + name
                if full not in imported:
                    self.docker(
                        "exec",
                        node,
                        "ctr",
                        "--namespace",
                        "k8s.io",
                        "images",
                        "tag",
                        name,
                        full,
                    )
                self.docker(
                    "exec",
                    node,
                    "ctr",
                    "--namespace",
                    "k8s.io",
                    "images",
                    "rm",
                    name,
                )
        for _ in range(20):
            status = self.docker(
                "exec",
                node,
                "crictl",
                "inspecti",
                reference,
                check=False,
            )
            if status.returncode == 0:
                identity = json.loads(status.stdout).get("status", {}).get("id")
                if identity:
                    if identity not in {expected_config, pinned_manifest}:
                        raise RuntimeError(
                            "CRI image differs from verified OCI content"
                        )
                    break
            time.sleep(0.5)
        else:
            raise RuntimeError("CRI did not register the pinned image")

    def create(self, run):
        with self.lock:
            deps = self.dependencies(run)
            self.ensure_network()
            if "kubernetes" in deps:
                self.ensure_cluster()
            names = self.names(run)
            path = self.state / "bays" / run["id"]
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
            client = path / "client"
            client.mkdir(mode=0o755, exist_ok=True)
            # mkdir's mode is filtered by the service's private UMask=0077.
            # Only this read-only bind root needs traversal by container UID1000;
            # its host-side ancestors remain private to the backend account.
            client.chmod(0o755)
            if "ansible" in deps:
                self.command(
                    (
                        "ssh-keygen",
                        "-q",
                        "-t",
                        "ed25519",
                        "-N",
                        "",
                        "-f",
                        str(path / "id_ed25519"),
                    )
                )
                (client / "authorized_keys").write_text(
                    (path / "id_ed25519.pub").read_text()
                )
                (client / "authorized_keys").chmod(0o644)
            if "kubernetes" in deps:
                namespace = {
                    "apiVersion": "v1",
                    "kind": "Namespace",
                    "metadata": {
                        "name": self.namespace(run),
                        "labels": {
                            "devops-quests": "true",
                            "devops-quests.installation": self.installation,
                            "devops-quests.run": run["id"],
                            "pod-security.kubernetes.io/enforce": "restricted",
                            "pod-security.kubernetes.io/enforce-version": "latest",
                        },
                    },
                }
                self.kube("create", "-f", "-", input=json.dumps(namespace))
                self.kube(
                    "-n", self.namespace(run), "create", "serviceaccount", "player"
                )
                role = {
                    "apiVersion": "rbac.authorization.k8s.io/v1",
                    "kind": "Role",
                    "metadata": {"name": "player", "namespace": self.namespace(run)},
                    "rules": [
                        {
                            "apiGroups": [
                                "",
                                "apps",
                                "batch",
                                "policy",
                                "networking.k8s.io",
                                "rbac.authorization.k8s.io",
                                "argoproj.io",
                            ],
                            "resources": [
                                "pods",
                                "pods/log",
                                "pods/exec",
                                "pods/eviction",
                                "services",
                                "endpoints",
                                "configmaps",
                                "secrets",
                                "persistentvolumeclaims",
                                "serviceaccounts",
                                "deployments",
                                "deployments/scale",
                                "replicasets",
                                "replicasets/scale",
                                "statefulsets",
                                "statefulsets/scale",
                                "jobs",
                                "cronjobs",
                                "poddisruptionbudgets",
                                "roles",
                                "rolebindings",
                                "events",
                                "networkpolicies",
                                "applications",
                            ],
                            "verbs": ["*"],
                        }
                    ],
                }
                role["rules"].append(
                    {
                        "apiGroups": ["discovery.k8s.io"],
                        "resources": ["endpointslices"],
                        "verbs": ["get", "list", "watch"],
                    }
                )
                if run["level"] == 103:
                    role["rules"].append(
                        {
                            "apiGroups": ["apps"],
                            "resources": ["daemonsets"],
                            "verbs": ["*"],
                        }
                    )
                if "ingress" in deps:
                    role["rules"].append(
                        {
                            "apiGroups": ["networking.k8s.io"],
                            "resources": ["ingresses"],
                            "verbs": ["*"],
                        }
                    )
                if "operator" in deps:
                    role["rules"].append(
                        {
                            "apiGroups": ["training.devops-quests.local"],
                            "resources": ["stationboards"],
                            "verbs": ["*"],
                        }
                    )
                if run["level"] == 126:
                    role["rules"].append(
                        {
                            "apiGroups": [""],
                            "resources": ["resourcequotas", "limitranges"],
                            "verbs": ["*"],
                        }
                    )
                if "metrics" in deps:
                    role["rules"] += [
                        {
                            "apiGroups": ["autoscaling"],
                            "resources": ["horizontalpodautoscalers"],
                            "verbs": ["*"],
                        },
                        {
                            "apiGroups": ["metrics.k8s.io"],
                            "resources": ["pods"],
                            "verbs": ["get", "list"],
                        },
                    ]
                if "gateway" in deps:
                    role["rules"].append(
                        {
                            "apiGroups": ["gateway.networking.k8s.io"],
                            "resources": ["gateways", "httproutes"],
                            "verbs": ["*"],
                        }
                    )
                self.kube("apply", "-f", "-", input=json.dumps(role))
                self.kube(
                    "-n",
                    self.namespace(run),
                    "create",
                    "rolebinding",
                    "player",
                    "--role=player",
                    "--serviceaccount=" + self.namespace(run) + ":player",
                )
                # `k get ns` is a supported discovery command. Grant only
                # namespace metadata reads in this dedicated training cluster.
                self.namespace_reader(run)
                token = self.kube(
                    "-n",
                    self.namespace(run),
                    "create",
                    "token",
                    "player",
                    "--duration=24h",
                ).stdout.strip()
                import yaml

                config = yaml.safe_load(
                    self.kube("config", "view", "--raw", "--minify").stdout
                )
                ip = self.inspect(self.cluster + "-control-plane")["NetworkSettings"][
                    "Networks"
                ][self.network]["IPAddress"]
                config["clusters"][0]["cluster"]["server"] = "https://" + ip + ":6443"
                config["users"] = [{"name": "player", "user": {"token": token}}]
                config["contexts"][0]["context"].update(
                    user="player", namespace=self.namespace(run)
                )
                (client / "kubeconfig").write_text(yaml.safe_dump(config))
            else:
                (client / "kubeconfig").write_text(
                    "apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\n"
                )
            (client / "kubeconfig").chmod(0o644)
            need_docker = bool(deps & {"tofu", "registry"})
            volumes = {}
            for suffix in ("home", "docker", "certs") if need_docker else ("home",):
                name = names["workstation"] + "-" + suffix
                self.docker("volume", "create", *self.labels(), name)
                volumes[suffix] = name
            if need_docker:
                self.docker(
                    "run",
                    "-d",
                    "--name",
                    names["dind"],
                    *self.labels(),
                    "--network",
                    self.network,
                    "--network-alias",
                    "docker-" + run["id"],
                    "--privileged",
                    "--memory",
                    "1g",
                    "--memory-swap",
                    "1g",
                    "--cpus",
                    "0.75",
                    "--pids-limit",
                    "512",
                    "-v",
                    volumes["docker"] + ":/home/rootless/.local/share/docker",
                    "-v",
                    volumes["certs"] + ":/certs",
                    "--tmpfs",
                    "/var/lib/docker:rw,nosuid,nodev,size=1m",
                    "-e",
                    "DOCKER_TLS_CERTDIR=/certs",
                    "-e",
                    "DOCKER_TLS_SAN=DNS:docker-" + run["id"],
                    self.images["dind"],
                )
            if "ansible" in deps:
                for target in ("app1", "app2", "app3"):
                    self.docker(
                        "run",
                        "-d",
                        "--name",
                        names[target],
                        *self.labels(),
                        "--network",
                        self.network,
                        "--network-alias",
                        target + "-" + run["id"],
                        "--memory",
                        "96m",
                        "--memory-swap",
                        "96m",
                        "--cpus",
                        "0.25",
                        "--pids-limit",
                        "64",
                        "--cap-drop",
                        "ALL",
                        *functools.reduce(
                            operator.iadd,
                            (
                                ["--cap-add", cap]
                                for cap in (
                                    "CHOWN",
                                    "DAC_OVERRIDE",
                                    "SETUID",
                                    "SETGID",
                                    "SYS_CHROOT",
                                    "AUDIT_WRITE",
                                )
                            ),
                            [],
                        ),
                        "--security-opt",
                        "no-new-privileges",
                        "--mount",
                        f"type=bind,src={client},dst=/run/dq,readonly",
                        self.image,
                        "target",
                    )
            docker_args = (
                [
                    "-v",
                    volumes["certs"] + ":/run/docker-certs:ro",
                    "-e",
                    "DOCKER_HOST=tcp://docker-" + run["id"] + ":2376",
                    "-e",
                    "DOCKER_TLS_VERIFY=1",
                    "-e",
                    "DOCKER_CERT_PATH=/run/docker-certs/client",
                ]
                if need_docker
                else []
            )
            self.docker(
                "run",
                "-d",
                "--name",
                names["workstation"],
                *self.labels(),
                "--network",
                self.network,
                "--user",
                "1000:1000",
                "--memory",
                "512m",
                "--memory-swap",
                "512m",
                "--cpus",
                "1",
                "--pids-limit",
                "256",
                "--cap-drop",
                "ALL",
                "--security-opt",
                "no-new-privileges",
                "--read-only",
                "--tmpfs",
                "/tmp:rw,noexec,nosuid,size=128m,mode=1777",
                "-v",
                volumes["home"] + ":/home/hacker",
                *docker_args,
                "--mount",
                f"type=bind,src={client},dst=/run/dq,readonly",
                "-e",
                "KUBECONFIG=/run/dq/kubeconfig",
                "-e",
                "DQ_NAMESPACE=" + self.namespace(run),
                "-e",
                "DQ_NODE_NAME=" + self.cluster + "-control-plane",
                "-e",
                "DQ_APP_IMAGE=" + self.images["app"],
                self.image,
            )
            self.exec(run, "mkdir -p ~/quest; printf '\\ncd ~/quest\\n' >> ~/.bashrc")
            if "ansible" in deps:
                key = base64.b64encode((path / "id_ed25519").read_bytes()).decode()
                hosts = []
                for target in ("app1", "app2", "app3"):
                    for _ in range(40):
                        result = self.docker(
                            "exec",
                            names[target],
                            "cat",
                            "/etc/ssh/ssh_host_ed25519_key.pub",
                            check=False,
                        )
                        public = result.stdout.strip().split()
                        if result.returncode == 0 and len(public) >= 2:
                            break
                        time.sleep(0.25)
                    else:
                        raise RuntimeError("Managed target host key was not generated")
                    hosts.append(
                        "["
                        + target
                        + "-"
                        + run["id"]
                        + "]:2222 "
                        + " ".join(public[:2])
                    )
                inventory = (
                    "[fleet]\n"
                    + "\n".join(
                        f"{t} ansible_host={t}-{run['id']} ansible_port=2222 ansible_user=root"
                        for t in ("app1", "app2", "app3")
                    )
                    + "\n"
                )
                script = (
                    "umask 077\nmkdir -p ~/.ssh\nprintf %s "
                    + shlex.quote(key)
                    + " | base64 -d > ~/.ssh/id_ed25519\n"
                )
                for file, content in {
                    "/home/hacker/.ssh/known_hosts": "\n".join(hosts) + "\n",
                    "/home/hacker/quest/inventory.ini": inventory,
                    "/home/hacker/quest/ansible.cfg": "[defaults]\ninventory=inventory.ini\nhost_key_checking=True\ninterpreter_python=/usr/bin/python3\n",
                }.items():
                    script += (
                        "cat > "
                        + shlex.quote(file)
                        + " <<'DQEOF'\n"
                        + content
                        + "DQEOF\n"
                    )
                self.exec(run, script)
            if need_docker:
                for _ in range(40):
                    if (
                        self.exec(
                            run, "docker info >/dev/null 2>&1", check=False
                        ).returncode
                        == 0
                    ):
                        break
                    time.sleep(1)
                else:
                    raise RuntimeError("The private Docker daemon did not start.")
                archive = self.root / ".state/app-oci.tar"
                with archive.open("rb") as source:
                    subprocess.run(
                        [
                            *DOCKER,
                            "exec",
                            "-i",
                            names["dind"],
                            "docker",
                            "--host",
                            "unix:///run/user/1000/docker.sock",
                            "load",
                        ],
                        stdin=source,
                        capture_output=True,
                        check=True,
                    )
                if "registry" in deps:
                    with (self.root / ".state/private-oci.tar").open("rb") as source:
                        subprocess.run(
                            [
                                *DOCKER,
                                "exec",
                                "-i",
                                names["dind"],
                                "docker",
                                "--host",
                                "unix:///run/user/1000/docker.sock",
                                "load",
                            ],
                            stdin=source,
                            capture_output=True,
                            check=True,
                        )
            if "kubernetes" in deps:
                self.exec(run, "kubectl get pods >/dev/null")
            if deps & {"gitea", "registry", "vault", "argocd"}:
                from .platform import Platform

                Platform(self).create(run)
            if "applicationset" in deps:
                from .application_sets import ApplicationSets

                ApplicationSets(self).create(run)
            if run["level"] in {124, 129}:
                from .recovery_fixtures import RecoveryFixtures

                RecoveryFixtures(self).create(run)
            if "prometheus" in deps:
                from .prometheus import Prometheus

                Prometheus(self).create(run)
            if "webhook" in deps:
                from .admission import Admission

                Admission(self).create(run)
            if "operator" in deps:
                from .book_runtime import install_operator

                install_operator(self, run)
            if run["level"] == 118:
                from .book_runtime import proxy_observation

                proxy_observation(self, run)
            if deps & {"metrics", "gateway"}:
                from .book_components import BookComponents

                BookComponents(self).create(run)
            if deps & {"dns", "ingress"}:
                from .components import Components

                Components(self).create(run)

    def namespace_reader(self, run):
        name = "dq-" + self.installation + "-namespace-reader"
        binding = self.namespace(run) + "-namespace-reader"
        label = {"devops-quests.installation": self.installation}
        objects = [
            {
                "apiVersion": "rbac.authorization.k8s.io/v1",
                "kind": "ClusterRole",
                "metadata": {"name": name, "labels": label},
                "rules": [
                    {
                        "apiGroups": [""],
                        "resources": ["namespaces"],
                        "verbs": ["get", "list"],
                    }
                ],
            },
            {
                "apiVersion": "rbac.authorization.k8s.io/v1",
                "kind": "ClusterRoleBinding",
                "metadata": {"name": binding, "labels": label},
                "roleRef": {
                    "apiGroup": "rbac.authorization.k8s.io",
                    "kind": "ClusterRole",
                    "name": name,
                },
                "subjects": [
                    {
                        "kind": "ServiceAccount",
                        "name": "player",
                        "namespace": self.namespace(run),
                    }
                ],
            },
        ]
        for obj in objects:
            found = self.kube(
                "get",
                obj["kind"],
                obj["metadata"]["name"],
                "-o",
                "json",
                "--ignore-not-found",
                check=False,
            )
            if found.returncode or (
                found.stdout.strip()
                and json.loads(found.stdout)["metadata"]
                .get("labels", {})
                .get("devops-quests.installation")
                != self.installation
            ):
                raise RuntimeError("Cannot verify namespace reader ownership")
            self.kube("apply", "-f", "-", input=json.dumps(obj))

    def remove_namespace(self, name):
        result = self.kube(
            "get", "namespace", name, "-o", "json", "--ignore-not-found", check=False
        )
        if result.returncode:
            raise RuntimeError("Cannot verify namespace ownership")
        namespace_exists = bool(result.stdout.strip())
        if namespace_exists:
            labels = json.loads(result.stdout)["metadata"].get("labels", {})
            if labels.get("devops-quests.installation") != self.installation:
                raise RuntimeError("Refusing a foreign namespace")
        binding = name + "-namespace-reader"
        found = self.kube(
            "get",
            "clusterrolebinding",
            binding,
            "-o",
            "json",
            "--ignore-not-found",
            check=False,
        )
        if found.returncode:
            raise RuntimeError("Cannot verify namespace reader binding")
        if found.stdout.strip():
            if (
                json.loads(found.stdout)["metadata"]
                .get("labels", {})
                .get("devops-quests.installation")
                != self.installation
            ):
                raise RuntimeError("Refusing a foreign namespace reader binding")
            self.kube("delete", "clusterrolebinding", binding)
        if not namespace_exists:
            return
        self.kube("delete", "namespace", name, "--wait=false")
        # Only after the ownership gate and termination admission barrier:
        # shorten grace for disposable training processes, without --force.
        self.kube(
            "-n",
            name,
            "delete",
            "pods",
            "--all",
            "--grace-period=1",
            "--wait=false",
            check=False,
        )
        self.kube(
            "wait", "--for=delete", "namespace/" + name, "--timeout=60s", timeout=90
        )

    def game_controls(self, run):
        from .platform import Platform

        if run["level"] == 123:
            from .application_sets import ApplicationSets

            ApplicationSets(self).control(run)
        elif run["level"] == 121:
            from .admission import Admission

            Admission(self).control(run)
        else:
            Platform(self).game_controls(run)

    def observe(self, run):
        from .sandbox_evidence import observe

        observe(self, run)
        if run["level"] == 117:
            from .static_pods import control

            control(self, run)

        if run["level"] == 116:
            from .book_runtime import reconcile

            reconcile(self, run)

    def capture_facts(self, run, files):
        """Freeze setup evidence in the existing read-only client bind mount."""
        if not re.fullmatch(r"[a-f0-9]{24}", run["id"]):
            raise ValueError("Invalid fact bay identity")
        stage = run["stage"]
        if type(stage) is not int or not 0 <= stage <= 20:
            raise ValueError("Invalid fact stage")
        if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", f) for f in files):
            raise ValueError("Invalid fact filename")
        folder = self.state / "bays" / run["id"] / "client" / "facts" / str(stage)
        folder.mkdir(mode=0o755, parents=True, exist_ok=True)
        folder.parent.chmod(0o755)
        folder.chmod(0o755)
        for name in files:
            result = self.exec(run, "head -c 65537 -- ~/quest/" + shlex.quote(name))
            content = result.stdout.encode()
            if len(content) > 65536:
                raise ValueError("Fact exceeds size bound")
            path = folder / name
            if path.exists():
                if path.read_bytes() != content:
                    raise RuntimeError("Refusing to overwrite frozen setup evidence")
            else:
                path.write_bytes(content)
                path.chmod(0o444)

    def remove_bay_files(self, run):
        identifier = run["id"]
        if not re.fullmatch(r"[a-f0-9]{24}", identifier):
            raise RuntimeError("Refusing an invalid bay directory")
        bays = self.state / "bays"
        path = bays / identifier
        if bays.is_symlink() or path.is_symlink():
            raise RuntimeError("Refusing a linked bay directory")
        if path.exists():
            shutil.rmtree(path)

    def teardown(self, run):
        with self.lock:
            if run["level"] == 129:
                from .recovery_fixtures import RecoveryFixtures

                RecoveryFixtures(self).before_namespace(run)
            if "prometheus" in self.dependencies(run):
                from .prometheus import Prometheus

                Prometheus(self).teardown(run)
            if "webhook" in self.dependencies(run):
                from .admission import Admission

                Admission(self).teardown(run)
            if run["level"] == 117:
                from .static_pods import teardown

                teardown(self, run)
            if self.dependencies(run) & {"metrics", "gateway"}:
                from .book_components import BookComponents

                BookComponents(self).teardown(run)
            if self.dependencies(run) & {"dns", "ingress"}:
                from .components import Components

                Components(self).teardown(run)
            for name in self.names(run).values():
                self.remove_container(name)
            if self.dependencies(run) & {"gitea", "registry", "vault", "argocd"}:
                from .platform import Platform

                Platform(self).teardown(run)
            if "kubernetes" in self.dependencies(run) and self.kubeconfig.exists():
                node = self.inspect(self.cluster + "-control-plane")
                if node and node["State"]["Running"]:
                    self.remove_namespace(self.namespace(run))
            if run["level"] == 124:
                from .recovery_fixtures import RecoveryFixtures

                RecoveryFixtures(self).after_namespace(run)
            for suffix in ("home", "docker", "certs"):
                name = self.names(run)["workstation"] + "-" + suffix
                result = self.docker("volume", "inspect", name, check=False)
                if result.returncode == 0:
                    data = json.loads(result.stdout)[0]
                    if (
                        data.get("Labels", {}).get("devops-quests.installation")
                        != self.installation
                    ):
                        raise RuntimeError("Refusing a foreign volume")
                    self.docker("volume", "rm", name)
            self.remove_bay_files(run)
            node = self.inspect(self.cluster + "-control-plane")
            others = self.docker(
                "ps", "-q", "--filter", "label=" + self.label
            ).stdout.split()
            marker = self.state / "kind-owner"
            identity = self.state / "kind-node-id"
            owns_node = (
                node
                and marker.is_file()
                and marker.read_text() == self.installation
                and identity.is_file()
                and identity.read_text() == node["Id"]
                and node["Config"]["Image"] == self.kind_image
                and node["Config"].get("Labels", {}).get("io.x-k8s.kind.cluster")
                == self.cluster
                and self.network in node["NetworkSettings"]["Networks"]
            )
            if owns_node and node["State"]["Running"] and not others:
                self.docker("stop", "--time", "15", node["Id"], timeout=60)

    def reset(self):
        with self.lock:
            ids = self.docker(
                "ps", "-aq", "--filter", "label=" + self.label
            ).stdout.split()
            for identifier in ids:
                self.remove_container(identifier)
            marker = self.state / "kind-owner"
            if marker.exists() and marker.read_text() == self.installation:
                node = self.inspect(self.cluster + "-control-plane")
                if node and (
                    node["Config"]["Image"] != self.kind_image
                    or self.network not in node["NetworkSettings"]["Networks"]
                ):
                    raise RuntimeError("Refusing a replaced kind node")
                env = dict(
                    os.environ,
                    DOCKER_HOST="unix:///var/run/docker.sock",
                    KIND_EXPERIMENTAL_DOCKER_NETWORK=self.network,
                )
                subprocess.run(
                    [
                        str(self.root / "bin/kind"),
                        "delete",
                        "cluster",
                        "--name",
                        self.cluster,
                        "--kubeconfig",
                        str(self.kubeconfig),
                    ],
                    env=env,
                    check=True,
                    capture_output=True,
                )
                marker.unlink()
            ids = self.docker(
                "volume", "ls", "-q", "--filter", "label=" + self.label
            ).stdout.split()
            for identifier in ids:
                self.docker("volume", "rm", identifier)
            result = self.docker("network", "inspect", self.network, check=False)
            if result.returncode == 0:
                if (
                    json.loads(result.stdout)[0]
                    .get("Labels", {})
                    .get("devops-quests.installation")
                    != self.installation
                ):
                    raise RuntimeError("Refusing a foreign network")
                self.firewall(remove=True)
                self.docker("network", "rm", self.network)

            bays = self.state / "bays"
            if bays.is_symlink():
                raise RuntimeError("Refusing a linked bay root")
            if bays.exists():
                for path in bays.iterdir():
                    self.remove_bay_files({"id": path.name})

    def topology(self, run):
        deps = self.dependencies(run)
        names = self.names(run)
        roles = ["workstation"]
        if "ansible" in deps:
            roles += ["app1", "app2", "app3"]
        if deps & {"tofu", "registry"}:
            roles.append("dind")
        nodes = []
        for role in roles:
            data = self.inspect(names[role])
            nodes.append(
                {
                    "id": role,
                    "name": role,
                    "state": "Running"
                    if data and data["State"]["Running"]
                    else "Unavailable",
                }
            )
        if deps & {"gitea", "registry", "vault"}:
            from .platform import Platform

            platform = Platform(self)
            for role in ("gitea", "registry", "vault"):
                if role in deps:
                    data = self.inspect(platform.name(run, role))
                    nodes.append(
                        {
                            "id": role,
                            "name": role,
                            "state": "Running"
                            if data and data["State"]["Running"]
                            else "Unavailable",
                        }
                    )
        if deps & {"tofu", "registry"}:
            result = self.exec(
                run, "docker ps -a --format '{{json .}}'", check=False, timeout=10
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines()[:8]:
                    obj = json.loads(line)
                    nodes.append(
                        {
                            "id": "tofu-" + obj["ID"],
                            "name": obj["Names"],
                            "state": "Running"
                            if obj["State"] == "running"
                            else obj["State"],
                        }
                    )
        if "kubernetes" not in deps:
            return nodes
        data = self.inspect(self.cluster + "-control-plane")
        nodes.append(
            {
                "id": "kind",
                "name": "kind",
                "state": "Running"
                if data and data["State"]["Running"]
                else "Unavailable",
            }
        )
        result = self.kube(
            "-n", self.namespace(run), "get", "pods", "-o", "json", check=False
        )
        if result.returncode == 0:
            for pod in json.loads(result.stdout)["items"][:8]:
                pod_status = pod.get("status", {})
                statuses = pod_status.get("containerStatuses", [])
                waiting = next(
                    (
                        c["state"]["waiting"].get("reason")
                        for c in statuses
                        if c.get("state", {}).get("waiting")
                    ),
                    None,
                )
                ready = any(
                    c["type"] == "Ready" and c["status"] == "True"
                    for c in pod_status.get("conditions", [])
                )
                phase = pod_status.get("phase", "Pending")
                nodes.append(
                    {
                        "id": pod["metadata"]["name"],
                        "name": pod["metadata"]["name"],
                        "state": waiting
                        or ("NotReady" if phase == "Running" and not ready else phase),
                    }
                )
        result = self.kube(
            "-n",
            self.namespace(run),
            "get",
            "endpointslices",
            "-o",
            "json",
            check=False,
        )
        if result.returncode == 0:
            for service in json.loads(result.stdout)["items"][:4]:
                name = service["metadata"]["labels"].get(
                    "kubernetes.io/service-name", "service"
                )
                healthy = any(
                    e.get("conditions", {}).get("ready")
                    for e in (service.get("endpoints") or [])
                )
                nodes.append(
                    {
                        "id": "service-" + name,
                        "name": name,
                        "state": "Running" if healthy else "NoEndpoints",
                    }
                )
        if "argocd" in deps:
            result = self.kube(
                "-n",
                "dq-platform-" + run["id"]
                if run["level"] == 123
                else self.namespace(run),
                "get",
                "applications",
                "-o",
                "json",
                check=False,
            )
            if result.returncode == 0:
                for app in json.loads(result.stdout)["items"][:3]:
                    nodes.append(
                        {
                            "id": "argo-" + app["metadata"]["name"],
                            "name": "Argo " + app["metadata"]["name"],
                            "state": app.get("status", {})
                            .get("sync", {})
                            .get("status", "Pending"),
                        }
                    )
        return nodes
