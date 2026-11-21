set -euo pipefail
cd ~/quest
sed -i 's/content = "retired\\n"/content = file("${path.module}\/approved-release.txt")/' main.tf
tofu apply -auto-approve -input=false -no-color
