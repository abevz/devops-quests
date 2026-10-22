"""Download verified tools and build the versioned local workstation image."""

import hashlib
import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = {
    "crane": (
        "https://github.com/google/go-containerregistry/releases/download/v0.22.1/go-containerregistry_Linux_x86_64.tar.gz",
        "https://github.com/google/go-containerregistry/releases/download/v0.22.1/checksums.txt",
        "crane",
    ),
    "kind": (
        "https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64",
        ".sha256sum",
        None,
    ),
    "kubectl": (
        "https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl",
        ".sha256",
        None,
    ),
    "helm": (
        "https://get.helm.sh/helm-v4.3.1-linux-amd64.tar.gz",
        ".sha256sum",
        "linux-amd64/helm",
    ),
    "tofu": (
        "https://github.com/opentofu/opentofu/releases/download/v1.13.1/tofu_1.13.1_linux_amd64.tar.gz",
        "https://github.com/opentofu/opentofu/releases/download/v1.13.1/tofu_1.13.1_SHA256SUMS",
        "tofu",
    ),
}


def get(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()


def main():
    (ROOT / ".state").mkdir(mode=0o700, exist_ok=True)
    manifest_path = ROOT / "tools.lock.json"
    recorded = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for name, (url, checksum, member) in TOOLS.items():
        target = ROOT / "bin" / name
        if target.exists() and name in recorded:
            if (
                hashlib.sha256(target.read_bytes()).hexdigest()
                == recorded[name]["binary_sha256"]
            ):
                continue
            raise RuntimeError(f"{name} checksum changed; refusing execution")
        checksum_url = checksum if checksum.startswith("https://") else url + checksum
        sums = get(checksum_url).decode()
        filename = url.rsplit("/", 1)[-1]
        lines = [line for line in sums.splitlines() if filename in line]
        expected = (lines[0] if lines else sums).split()[0]
        payload = get(url)
        if hashlib.sha256(payload).hexdigest() != expected:
            raise RuntimeError(f"{name}: archive checksum mismatch")
        if member:
            with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
                payload = archive.extractfile(member).read()
        target.write_bytes(payload)
        target.chmod(0o755)
        recorded[name] = {
            "url": url,
            "checksum_url": checksum_url,
            "download_sha256": expected,
            "binary_sha256": hashlib.sha256(payload).hexdigest(),
        }
        manifest_path.write_text(json.dumps(recorded, indent=2) + "\n")
        print(f"Verified {name}", flush=True)
    images = json.loads((ROOT / "images.lock.json").read_text())
    docker = ["docker", "--host", "unix:///var/run/docker.sock"]
    for key in (
        "app",
        "argocd",
        "redis",
        "coredns",
        "traefik",
        "metrics",
        "prometheus",
    ):
        archive = ROOT / ".state" / (key + "-oci.tar")
        recorded_archive = archive.with_suffix(".ref")
        if archive.is_dir():
            # crane OCI output is an OCI-layout directory, not a tarball.
            previous = archive.with_suffix(".layout")
            if previous.exists():
                shutil.rmtree(previous)
            archive.rename(previous)
        if (
            not archive.is_file()
            or not recorded_archive.exists()
            or recorded_archive.read_text() != images[key] + " canonical-v2"
        ):
            with tempfile.TemporaryDirectory(
                prefix="oci-", dir=ROOT / ".state"
            ) as directory:
                layout = Path(directory) / "image"
                subprocess.run(
                    [
                        str(ROOT / "bin/crane"),
                        "pull",
                        images[key],
                        str(layout),
                        "--format=oci",
                        "--annotate-ref",
                        "--platform=linux/amd64",
                    ],
                    check=True,
                )
                index_path = layout / "index.json"
                index = json.loads(index_path.read_text())
                manifest = index["manifests"][0]
                if manifest["digest"] != images[key].split("@", 1)[1]:
                    raise RuntimeError("OCI manifest does not match the pinned digest")
                repository = images[key].split("@", 1)[0].rsplit(":", 1)[0]
                manifest.setdefault("annotations", {})[
                    "org.opencontainers.image.ref.name"
                ] = repository + "@" + manifest["digest"]
                index_path.write_text(json.dumps(index))
                with tarfile.open(archive, "w") as output:
                    for item in sorted(layout.iterdir()):
                        output.add(item, arcname=item.name)
            recorded_archive.write_text(images[key] + " canonical-v2")
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/derive_private_image.py")],
        check=True,
    )
    for key in ("kind", "dind", "app", "gitea", "registry", "vault", "argocd", "redis"):
        subprocess.run([*docker, "pull", images[key]], check=True)
    subprocess.run(
        [
            *docker,
            "build",
            "--build-arg",
            "KIND=" + images["kind"],
            "-t",
            "devops-quests/kind:0.1.0",
            "-f",
            "images/Kind.Dockerfile",
            ".",
        ],
        cwd=ROOT,
        check=True,
    )
    kind_id = subprocess.check_output(
        [
            *docker,
            "image",
            "inspect",
            "devops-quests/kind:0.1.0",
            "--format",
            "{{.Id}}",
        ],
        text=True,
    ).strip()
    (ROOT / ".state" / "kind-image.json").write_text(
        json.dumps({"id": kind_id, "upstream": images["kind"]}) + "\n"
    )
    subprocess.run(
        [
            *docker,
            "build",
            "--label",
            "devops-quests=true",
            "--build-arg",
            "BASE=" + images["base"],
            "--build-arg",
            "DOCKER_CLI=" + images["docker_cli"],
            "-t",
            "devops-quests/workstation:0.1.0",
            "-f",
            "images/Workstation.Dockerfile",
            ".",
        ],
        cwd=ROOT,
        check=True,
    )
    image_id = subprocess.check_output(
        [
            *docker,
            "image",
            "inspect",
            "devops-quests/workstation:0.1.0",
            "--format",
            "{{.Id}}",
        ],
        text=True,
    ).strip()
    (ROOT / ".state" / "built-image.json").write_text(
        json.dumps({"version": "0.1.0", "id": image_id}) + "\n"
    )


if __name__ == "__main__":
    main()
