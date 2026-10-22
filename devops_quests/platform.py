"""Ephemeral, game-only platform services; nothing contacts the homelab."""

import base64
import functools
import json
import operator
import secrets
import shlex
import time

import bcrypt
import yaml

from .sandbox_evidence import CONTROL_READER


class Platform:
    def __init__(self, runtime):
        self.r = runtime

    def name(self, run, role):
        return self.r.names(run)["workstation"] + "-" + role

    def namespace(self, run):
        return "dq-platform-" + run["id"]

    def put(self, run, name, content):
        return self.r.exec(
            run,
            "umask 077\ncat > ~/quest/"
            + shlex.quote(name)
            + " <<'DQPLATFORM'\n"
            + content
            + "\nDQPLATFORM\n",
        )

    def container(self, run, role, args, command=(), memory="192m"):
        name = self.name(run, role)
        declared = json.loads(
            self.r.docker("image", "inspect", self.r.images[role]).stdout
        )[0]["Config"].get("Volumes", {})
        mounts = []
        for i, target in enumerate(declared):
            volume = name + "-data" + str(i)
            self.r.docker("volume", "create", *self.r.labels(), volume)
            mounts.extend(["-v", volume + ":" + target])
        self.r.docker(
            "run",
            "-d",
            "--name",
            name,
            *self.r.labels(),
            "--network",
            self.r.network,
            "--network-alias",
            role + "-" + run["id"],
            "--memory",
            memory,
            "--memory-swap",
            memory,
            "--cpus",
            "0.5",
            "--pids-limit",
            "128",
            *mounts,
            *args,
            self.r.images[role],
            *command,
        )
        return name

    def wait(self, run, script, seconds=60):
        for _ in range(seconds):
            if self.r.exec(run, script, check=False).returncode == 0:
                return
            time.sleep(1)
        raise RuntimeError("Game platform service did not become ready.")

    def create(self, run):
        deps = self.r.dependencies(run)
        env = {}
        if "registry" in deps:
            env.update(self.registry(run))
        if "vault" in deps:
            env.update(self.vault(run))
        if "gitea" in deps:
            env.update(self.gitea(run))
        if run["level"] == 61:
            env["ARGO_NAMESPACE"] = self.namespace(run)
        self.put(
            run,
            "platform.env",
            "\n".join("export " + k + "=" + shlex.quote(v) for k, v in env.items()),
        )
        if "argocd" in deps:
            self.argocd(run, env)
        if run["level"] == 78:
            self.put(
                run,
                "registry-target.json",
                json.dumps(
                    {
                        "endpoint": env["REGISTRY"],
                        "image": env["PRIVATE_IMAGE"],
                    }
                ),
            )
            self.r.docker("stop", "--time", "5", self.name(run, "registry"))
        if run["level"] == 93:
            self.r.docker("stop", "--time", "5", self.name(run, "vault"))

    def game_controls(self, run):
        """Start one fixed owned service; never expose a host Docker proxy."""
        role = {78: "registry", 93: "vault"}.get(run["level"])
        if role is None:
            return
        request = self.r.exec(
            run,
            f"/usr/bin/python3 - {role}-repair.json <<'CONTROL_READ'\n"
            + CONTROL_READER
            + "\nCONTROL_READ\n",
            check=False,
            timeout=3,
        )
        if request.returncode:
            return
        try:
            data = json.loads(request.stdout)
        except (ValueError, TypeError):
            data = None
        if len(request.stdout) > 4096 or data != {"action": "start"}:
            self.put(run, role + "-agent-status.json", '{"status":"rejected"}')
            return
        name = self.name(run, role)
        obj = self.r.inspect(name)
        if (
            not obj
            or obj["Config"].get("Labels", {}).get("devops-quests.installation")
            != self.r.installation
            or obj["Config"]["Image"] != self.r.images[role]
            or obj["HostConfig"].get("NetworkMode") != self.r.network
            or obj["HostConfig"].get("Privileged")
        ):
            raise RuntimeError("Refusing a foreign or replaced game service")
        if not obj["State"]["Running"]:
            self.r.docker("start", name)
            readiness = (
                'test "$(/usr/bin/curl -sS --max-time 1 '
                '--cacert /run/dq/facts/0/registry-ca.crt -o /dev/null -w "%{http_code}" '
                + shlex.quote("https://registry-" + run["id"] + ":5000/v2/")
                + ')" = 401'
                if role == "registry"
                else "/usr/bin/curl -fsS --max-time 1 "
                + shlex.quote("http://vault-" + run["id"] + ":8200/v1/sys/init")
                + " | /usr/bin/jq -e '.initialized==true' >/dev/null"
            )
            self.wait(run, readiness, seconds=10)
        self.put(run, role + "-agent-status.json", '{"status":"started"}')

    def registry(self, run):
        r = self.r
        folder = r.state / "bays" / run["id"] / "registry"
        folder.mkdir(mode=0o755)
        folder.chmod(0o755)
        hostname = "registry-" + run["id"]
        password = secrets.token_urlsafe(18)
        r.command(
            (
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "2",
                "-subj",
                "/CN=" + hostname,
                "-addext",
                "subjectAltName=DNS:" + hostname,
                "-keyout",
                str(folder / "key.pem"),
                "-out",
                str(folder / "ca.crt"),
            )
        )
        (folder / "htpasswd").write_bytes(
            b"rail:" + bcrypt.hashpw(password.encode(), bcrypt.gensalt()) + b"\n"
        )
        for f in folder.iterdir():
            f.chmod(0o644)
        self.container(
            run,
            "registry",
            [
                "--cap-drop",
                "ALL",
                "--security-opt",
                "no-new-privileges",
                "--mount",
                f"type=bind,src={folder},dst=/credentials,readonly",
                "-e",
                "REGISTRY_HTTP_TLS_CERTIFICATE=/credentials/ca.crt",
                "-e",
                "REGISTRY_HTTP_TLS_KEY=/credentials/key.pem",
                "-e",
                "REGISTRY_AUTH=htpasswd",
                "-e",
                "REGISTRY_AUTH_HTPASSWD_REALM=SignalRail",
                "-e",
                "REGISTRY_AUTH_HTPASSWD_PATH=/credentials/htpasswd",
                *(
                    ["-e", "REGISTRY_STORAGE_DELETE_ENABLED=true"]
                    if run["level"] in {66, 97}
                    else []
                ),
            ],
            memory="96m",
        )
        endpoint = hostname + ":5000"
        dind = r.names(run)["dind"]
        node = r.cluster + "-control-plane"
        for name in (dind, node) if "kubernetes" in r.dependencies(run) else (dind,):
            destination = (
                "/home/rootless/.config/docker/certs.d/"
                if name == dind
                else "/etc/containerd/certs.d/"
            ) + endpoint
            r.docker("exec", name, "mkdir", "-p", destination)
            r.docker("cp", str(folder / "ca.crt"), name + ":" + destination + "/ca.crt")
            if name == node:
                hosts = (
                    'server = "https://'
                    + endpoint
                    + '"\n[host."https://'
                    + endpoint
                    + '"]\n capabilities = ["pull", "resolve"]\n ca = "'
                    + destination
                    + '/ca.crt"\n'
                )
                r.docker(
                    "exec",
                    "-i",
                    node,
                    "sh",
                    "-c",
                    "cat > " + shlex.quote(destination + "/hosts.toml"),
                    input=hosts,
                )
        self.put(run, "registry-ca.crt", (folder / "ca.crt").read_text())
        script = (
            "printf %s "
            + shlex.quote(password)
            + " | docker login "
            + endpoint
            + " --username rail --password-stdin >/dev/null\n"
        )
        private_ref = json.loads((r.root / "images.derived.lock.json").read_text())[
            "private_app"
        ]["reference"]
        script += (
            "docker tag "
            + shlex.quote(private_ref)
            + " "
            + endpoint
            + "/parcel:1\ndocker push "
            + endpoint
            + "/parcel:1\n"
        )
        r.exec(run, script, timeout=120)
        digests = json.loads(
            r.exec(
                run,
                "docker image inspect "
                + endpoint
                + "/parcel:1 --format '{{json .RepoDigests}}'",
            ).stdout
        )
        pinned = next(x for x in digests if x.startswith(endpoint + "/parcel@"))
        return {
            "REGISTRY": endpoint,
            "REGISTRY_USER": "rail",
            "REGISTRY_PASSWORD": password,
            "PRIVATE_IMAGE": pinned,
        }

    def vault(self, run):
        r = self.r
        address = "http://vault-" + run["id"] + ":8200"
        config = {
            "disable_mlock": True,
            "storage": {"file": {"path": "/vault/file"}},
            "listener": {"tcp": {"address": "0.0.0.0:8200", "tls_disable": True}},
            "api_addr": address,
        }
        name = self.container(
            run,
            "vault",
            [
                "--cap-drop",
                "ALL",
                "--cap-add",
                "CHOWN",
                "--cap-add",
                "SETUID",
                "--cap-add",
                "SETGID",
                "-e",
                "VAULT_LOCAL_CONFIG=" + json.dumps(config),
                "-e",
                "VAULT_ADDR=http://127.0.0.1:8200",
            ],
            ["server"],
            memory="256m",
        )
        self.wait(
            run,
            "curl -s "
            + address
            + "/v1/sys/init | jq -e ' .initialized==false' >/dev/null",
        )
        initialized = json.loads(
            r.docker(
                "exec",
                name,
                "vault",
                "operator",
                "init",
                "-key-shares=3",
                "-key-threshold=2",
                "-format=json",
            ).stdout
        )
        private = r.state / "bays" / run["id"] / "vault-init.json"
        private.write_text(json.dumps(initialized))
        private.chmod(0o600)
        for key in initialized["unseal_keys_b64"][:2]:
            r.docker("exec", name, "vault", "operator", "unseal", key)

        def vault(*args, input=None):
            return r.docker(
                "exec",
                "-i",
                "-e",
                "VAULT_TOKEN=" + initialized["root_token"],
                name,
                "vault",
                *args,
                input=input,
            )

        vault("secrets", "enable", "-path=secret", "kv-v2")
        vault("kv", "put", "secret/dispatch", "value=north-secret")
        renewal = run["level"] == 48
        sealed_recovery = run["level"] in {65, 93}
        reader_policy = (
            'path "secret/data/dispatch" { capabilities = ["read"] }\n'
            if renewal or sealed_recovery or run["level"] == 99
            else 'path "secret/data/wrong" { capabilities = ["read"] }\n'
        )
        vault(
            "policy",
            "write",
            "rail-reader",
            "-",
            input=reader_policy,
        )
        manager_policy = (
            'path "sys/policies/acl/rail-reader" { capabilities = ["read","update"] }\n'
        )
        if sealed_recovery:
            manager_policy = 'path "secret/data/dispatch" { capabilities = ["deny"] }\n'
        if renewal:
            vault(
                "write",
                "auth/token/roles/rail-station",
                "allowed_policies=rail-reader",
                "token_explicit_max_ttl=600",
                "renewable=true",
            )
            manager_policy = json.dumps(
                {
                    "path": {
                        "auth/token/create/rail-station": {
                            "capabilities": ["update"],
                            "required_parameters": [
                                "policies",
                                "ttl",
                                "renewable",
                                "explicit_max_ttl",
                            ],
                            "allowed_parameters": {
                                "policies": ["rail-reader"],
                                "ttl": ["60s"],
                                "renewable": [True],
                                "explicit_max_ttl": ["600s"],
                            },
                        }
                    }
                }
            )
        vault(
            "policy",
            "write",
            "rail-manager",
            "-",
            input=manager_policy,
        )
        reader = json.loads(
            vault(
                "token",
                "create",
                "-policy=rail-reader",
                "-format=json",
                *(["-ttl=45s", "-explicit-max-ttl=600s"] if renewal else []),
            ).stdout
        )["auth"]["client_token"]
        if run["level"] == 99:
            accessor = json.loads(
                vault("token", "lookup", "-format=json", reader).stdout
            )["data"]["accessor"]
            self.put(run, "compromised-accessor", accessor)
            vault(
                "write",
                "auth/token/roles/rail-rotation",
                "allowed_policies=rail-reader",
                "token_explicit_max_ttl=600",
                "renewable=false",
            )
            manager_policy = json.dumps(
                {
                    "path": {
                        "auth/token/create/rail-rotation": {
                            "capabilities": ["update"],
                            "required_parameters": [
                                "policies",
                                "ttl",
                                "renewable",
                                "explicit_max_ttl",
                            ],
                            "allowed_parameters": {
                                "policies": ["rail-reader"],
                                "ttl": ["300s"],
                                "renewable": [False],
                                "explicit_max_ttl": ["600s"],
                            },
                        },
                        "auth/token/revoke-accessor": {
                            "capabilities": ["update"],
                            "required_parameters": ["accessor"],
                            "allowed_parameters": {"accessor": [accessor]},
                        },
                    }
                }
            )
            vault("policy", "write", "rail-manager", "-", input=manager_policy)
        manager = json.loads(
            vault("token", "create", "-policy=rail-manager", "-format=json").stdout
        )["auth"]["client_token"]
        self.put(run, "reader.hcl", reader_policy)
        sync = """#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
value=$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)
kubectl create secret generic route-secret --from-literal=value="$value" --dry-run=client -o yaml | kubectl apply -f -
"""
        if renewal or run["level"] == 99:
            if renewal:
                self.put(run, "station-token", reader)
                r.exec(run, "chmod 600 ~/quest/station-token")
            sync = sync.replace(
                "value=$(curl", "VAULT_READER_TOKEN=$(cat station-token)\nvalue=$(curl"
            )
        self.put(run, "sync-secret.sh", sync)
        if sealed_recovery:
            if run["level"] == 93:
                status = json.loads(vault("status", "-format=json").stdout)
                self.put(run, "original-cluster-id", status["cluster_id"])
            self.put(
                run,
                "unseal-shares.json",
                json.dumps(initialized["unseal_keys_b64"][:2]),
            )
            r.exec(run, "chmod 600 ~/quest/unseal-shares.json")
            vault("operator", "seal")
        if run["level"] == 73:
            vault(
                "audit",
                "enable",
                "-path=station",
                "file",
                "file_path=/vault/file/station-audit.jsonl",
                "log_raw=false",
            )
            denied = r.docker(
                "exec",
                "-e",
                "VAULT_TOKEN=" + reader,
                name,
                "vault",
                "kv",
                "get",
                "-format=json",
                "secret/dispatch",
                check=False,
            )
            if denied.returncode == 0:
                raise RuntimeError("Audit fixture must record an actual denied read")
            raw = r.docker(
                "exec", name, "cat", "/vault/file/station-audit.jsonl"
            ).stdout
            events = self.audit_denials(raw)
            if len(events) != 1:
                raise RuntimeError(
                    "Audit fixture did not record exactly one denied read"
                )
            self.put(run, "audit-events.json", json.dumps(events))
        return {
            "VAULT_ADDR": address,
            "VAULT_READER_TOKEN": reader,
            "VAULT_MANAGER_TOKEN": manager,
        }

    @staticmethod
    def audit_denials(raw):
        """Export denial metadata only; never copy authentication or secret fields."""
        import re

        events = []
        for line in raw.splitlines():
            event = json.loads(line)
            request = event.get("request", {})
            if (
                event.get("type") == "response"
                and event.get("error")
                and request.get("path") == "secret/data/dispatch"
                and request.get("operation") == "read"
                and re.fullmatch(r"[a-f0-9-]{36}", request.get("id", ""))
            ):
                events.append(
                    {
                        "request_id": request["id"],
                        "path": request["path"],
                        "operation": "read",
                        "reason": "permission_denied",
                    }
                )
        return events

    def gitea(self, run):
        r = self.r
        host = "gitea-" + run["id"]
        password = secrets.token_urlsafe(18)
        env = {
            "GITEA__database__DB_TYPE": "sqlite3",
            "GITEA__security__INSTALL_LOCK": "true",
            "GITEA__service__DISABLE_REGISTRATION": "true",
            "GITEA__server__ROOT_URL": "http://" + host + ":3000/",
            "GITEA__server__DOMAIN": host,
            "GITEA__server__DISABLE_SSH": "true",
            "GITEA__security__SECRET_KEY": secrets.token_hex(32),
        }
        if run.get("level") == 75:
            node = r.inspect(r.cluster + "-control-plane")
            env["GITEA__webhook__ALLOWED_HOST_LIST"] = node["NetworkSettings"][
                "Networks"
            ][r.network]["IPAddress"]
        name = self.container(
            run,
            "gitea",
            [
                "--user",
                "1000:1000",
                "--cap-drop",
                "ALL",
                "--security-opt",
                "no-new-privileges",
                *functools.reduce(
                    operator.iadd, (["-e", k + "=" + v] for k, v in env.items()), []
                ),
            ],
            memory="256m",
        )
        self.wait(
            run,
            "curl -fsS --max-time 3 http://" + host + ":3000/api/healthz >/dev/null",
            seconds=180,
        )
        r.docker(
            "exec",
            "--user",
            "1000:1000",
            name,
            "gitea",
            "--config",
            "/etc/gitea/app.ini",
            "admin",
            "user",
            "create",
            "--username",
            "rail",
            "--password",
            password,
            "--email",
            "rail@example.invalid",
            "--must-change-password=false",
        )
        repo = "http://" + host + ":3000/rail/station.git"
        data = json.dumps({"name": "station", "private": True, "auto_init": False})
        r.exec(
            run,
            "curl -fsS -u "
            + shlex.quote("rail:" + password)
            + ' -H "Content-Type: application/json" -d '
            + shlex.quote(data)
            + " http://"
            + host
            + ":3000/api/v1/user/repos >/dev/null",
        )
        credential = base64.b64encode(("rail:" + password).encode()).decode()
        # Credentials belong only to this disposable private game repository.
        r.exec(
            run,
            "git config --global user.email rail@example.invalid\ngit config --global user.name SignalRail\ngit config --global http.extraHeader "
            + shlex.quote("Authorization: Basic " + credential)
            + "\ngit init -b main ~/quest/repository\n",
        )
        return {"GIT_URL": repo, "GIT_USER": "rail", "GIT_PASSWORD": password}

    def argocd(self, run, env):
        r = self.r
        ns = self.namespace(run)
        target = r.namespace(run)
        r.kube("create", "namespace", ns)
        r.kube(
            "label",
            "namespace",
            ns,
            "devops-quests=true",
            "devops-quests.installation=" + r.installation,
        )
        docs = list(
            yaml.safe_load_all((r.root / "vendor/argocd-install.yaml").read_text())
        )
        selected = []
        keep_workloads = {
            "argocd-application-controller",
            "argocd-repo-server",
            "argocd-redis",
        }
        appsets = "applicationset" in r.dependencies(run)
        if appsets:
            keep_workloads.add("argocd-applicationset-controller")
        webhook_secret = secrets.token_urlsafe(24) if run["level"] == 75 else None
        if webhook_secret:
            keep_workloads.add("argocd-server")
        for obj in docs:
            if not obj:
                continue
            kind = obj["kind"]
            name = obj["metadata"]["name"]
            if kind in ("Deployment", "StatefulSet") and name not in keep_workloads:
                continue
            if (
                appsets
                and kind == "ClusterRoleBinding"
                and name == "argocd-applicationset-controller"
            ):
                # The default single-namespace cache needs only its upstream
                # namespaced Role. Do not bind the cluster-wide equivalent.
                continue
            if kind == "NetworkPolicy":
                # Upstream HA policies assume omitted servers/controllers. This
                # owned minimal topology has separate bridge egress guards;
                # kindnet itself does enforce workload NetworkPolicy.
                continue
            if kind in ("Service", "ServiceAccount") and name not in keep_workloads:
                continue
            if kind not in (
                "CustomResourceDefinition",
                "ClusterRole",
                "ClusterRoleBinding",
                "Role",
                "RoleBinding",
                "ServiceAccount",
                "ConfigMap",
                "Secret",
                "Service",
                "Deployment",
                "StatefulSet",
            ):
                continue
            if kind not in (
                "CustomResourceDefinition",
                "ClusterRole",
                "ClusterRoleBinding",
            ):
                obj["metadata"]["namespace"] = ns
            for subject in obj.get("subjects", []):
                if subject.get("kind") == "ServiceAccount":
                    subject["namespace"] = ns
            if kind == "ClusterRoleBinding":
                obj["metadata"]["name"] = ns + "-" + name
            if webhook_secret and kind == "Service" and name == "argocd-server":
                obj["spec"]["type"] = "NodePort"
                obj["spec"]["ports"] = [
                    p for p in obj["spec"]["ports"] if p["name"] == "http"
                ]
            if webhook_secret and kind == "Secret" and name == "argocd-secret":
                obj.setdefault("stringData", {})["webhook.gogs.secret"] = webhook_secret
            if kind in ("Deployment", "StatefulSet"):
                spec = obj["spec"]["template"]["spec"]
                # Keep only non-HA components; rewrite each image to an immutable lock.
                for c in spec.get("containers", []) + spec.get("initContainers", []):
                    c["image"] = (
                        r.images["redis"]
                        if "redis" in c["image"]
                        else r.images["argocd"]
                    )
                    c["imagePullPolicy"] = "Never"
                    c["resources"] = {
                        "requests": {"cpu": "20m", "memory": "32Mi"},
                        "limits": {
                            "memory": "384Mi"
                            if name == "argocd-application-controller"
                            else "256Mi"
                            if name == "argocd-repo-server"
                            else "192Mi"
                            if name == "argocd-server"
                            else "96Mi"
                        },
                    }
                if name == "argocd-applicationset-controller":
                    spec["containers"][0]["resources"]["limits"] = {
                        "cpu": "300m",
                        "memory": "192Mi",
                    }
                if name == "argocd-application-controller":
                    spec["containers"][0].setdefault("args", []).extend(
                        [
                            "--application-namespaces",
                            target,
                            "--repo-server",
                            "argocd-repo-server." + ns + ".svc:8081",
                        ]
                    )
                if name == "argocd-server":
                    spec["containers"][0]["args"].append("--insecure")
            if kind == "ConfigMap" and name == "argocd-cm":
                obj["data"] = {
                    "application.resourceTrackingMethod": "annotation",
                    "timeout.reconciliation": "0" if webhook_secret else "15s",
                }
            if kind == "ConfigMap" and name == "argocd-cmd-params-cm":
                obj["data"] = {
                    "application.namespaces": target,
                    "repo.server": "argocd-repo-server." + ns + ".svc:8081",
                }
                if webhook_secret:
                    obj["data"]["server.log.format"] = "json"
                if appsets:
                    obj["data"]["applicationsetcontroller.enable.scm.providers"] = (
                        "false"
                    )

            selected.append(obj)
        # Preload only dependency-required pinned platform images in the owned node.
        for key in ("argocd", "redis"):
            r.load_image(key)
        r.kube(
            "apply",
            "--server-side",
            "-f",
            "-",
            input=yaml.safe_dump_all(selected),
            timeout=180,
        )
        project = {
            "apiVersion": "argoproj.io/v1alpha1",
            "kind": "AppProject",
            "metadata": {"name": "station", "namespace": ns},
            "spec": {
                "sourceNamespaces": [target],
                "sourceRepos": [env["GIT_URL"]],
                "destinations": [
                    {"server": "https://kubernetes.default.svc", "namespace": target}
                ],
                "clusterResourceWhitelist": [],
            },
        }
        repository = {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {
                "name": "station-repository",
                "namespace": ns,
                "labels": {"argocd.argoproj.io/secret-type": "repository"},
            },
            "stringData": {
                "url": env["GIT_URL"],
                "username": env["GIT_USER"],
                "password": env["GIT_PASSWORD"],
                "type": "git",
            },
        }
        r.kube("apply", "-f", "-", input=yaml.safe_dump_all([project, repository]))
        if run["level"] == 61:
            self.repository_access(run)
        for name in (
            "deployment/argocd-repo-server",
            "deployment/argocd-redis",
            "statefulset/argocd-application-controller",
        ):
            r.kube("-n", ns, "rollout", "status", name, "--timeout=120s", timeout=150)
        if appsets:
            r.kube(
                "-n",
                ns,
                "rollout",
                "status",
                "deployment/argocd-applicationset-controller",
                "--timeout=120s",
                timeout=150,
            )
        if webhook_secret:
            r.kube(
                "-n",
                ns,
                "rollout",
                "status",
                "deployment/argocd-server",
                "--timeout=120s",
                timeout=150,
            )
            service = json.loads(
                r.kube("-n", ns, "get", "service", "argocd-server", "-o", "json").stdout
            )
            port = next(
                p["nodePort"] for p in service["spec"]["ports"] if p["name"] == "http"
            )
            node = r.inspect(r.cluster + "-control-plane")
            ip = node["NetworkSettings"]["Networks"][r.network]["IPAddress"]
            webhook_url = f"http://{ip}:{port}/api/webhook"
            self.put(run, "webhook-target.json", json.dumps({"url": webhook_url}))
            self.put(
                run,
                "webhook.env",
                "\n".join(
                    [
                        "export WEBHOOK_URL=" + shlex.quote(webhook_url),
                        "export WEBHOOK_SECRET=" + shlex.quote(webhook_secret),
                    ]
                ),
            )

    def repository_access(self, run):
        """Permit one credential repair without general platform Secret access."""
        ns = self.namespace(run)
        role = {
            "apiVersion": "rbac.authorization.k8s.io/v1",
            "kind": "Role",
            "metadata": {"name": "repository-repair", "namespace": ns},
            "rules": [
                {
                    "apiGroups": [""],
                    "resources": ["secrets"],
                    "resourceNames": ["station-repository"],
                    "verbs": ["get", "patch", "update"],
                }
            ],
        }
        binding = {
            "apiVersion": "rbac.authorization.k8s.io/v1",
            "kind": "RoleBinding",
            "metadata": {"name": "repository-repair", "namespace": ns},
            "subjects": [
                {
                    "kind": "ServiceAccount",
                    "name": "player",
                    "namespace": self.r.namespace(run),
                }
            ],
            "roleRef": {
                "apiGroup": "rbac.authorization.k8s.io",
                "kind": "Role",
                "name": "repository-repair",
            },
        }
        self.r.kube("apply", "-f", "-", input=yaml.safe_dump_all([role, binding]))

    def teardown(self, run):
        r = self.r
        for role in ("gitea", "registry", "vault"):
            r.remove_container(self.name(run, role))
        for role in ("gitea", "registry", "vault"):
            volumes = r.docker(
                "volume", "ls", "-q", "--filter", "label=" + r.label
            ).stdout.split()
            for volume in volumes:
                if volume.startswith(self.name(run, role) + "-data"):
                    r.docker("volume", "rm", volume)
        if "argocd" in r.dependencies(run):
            # Explicit namespace and binding prefix; never touches another cluster.
            ns = self.namespace(run)
            r.remove_namespace(ns)
            bindings = json.loads(
                r.kube("get", "clusterrolebindings", "-o", "json").stdout
            )["items"]
            for binding in bindings:
                if binding["metadata"]["name"].startswith(ns + "-"):
                    r.kube("delete", "clusterrolebinding", binding["metadata"]["name"])
