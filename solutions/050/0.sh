set -euo pipefail
cd ~/quest
source platform.env
git -C repository cherry-pick release-candidate
git -C repository push origin main
