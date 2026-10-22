set -euo pipefail
cd ~/quest
source platform.env
test "$(sha256sum recovery-image.tar | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/archive.sha256)"
docker load -i recovery-image.tar
docker push "$REGISTRY/parcel:1"
