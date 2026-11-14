set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
variable "replicas" {
  description = "capacity-contract.json"
  type = number
  validation {
    condition = var.replicas >= 0
    error_message = "capacity-contract.json"
  }
}
variable "pool" {
  description = "capacity-contract.json"
  type = any
}
resource "local_file" "notice" {
  filename = "${path.root}/replicas.txt"
  content = tostring(var.replicas)
}
output "replicas" { value = var.replicas }
DQ_ASSET
cat > terraform.tfvars <<'DQ_ASSET'
replicas = 0
pool = { zones = ["north", "south"], slots_per_zone = 1 }
DQ_ASSET
cat > capacity-contract.json <<'DQ_ASSET'
{
  "replicas": {
    "integer": true,
    "minimum": 1,
    "maximum": 3
  },
  "pool": {
    "zones": {
      "nonempty": true,
      "distinct": true
    },
    "slots_per_zone": {
      "integer": true,
      "minimum": 1
    }
  },
  "capacity": "replicas <= length(pool.zones) * pool.slots_per_zone",
  "accept": [
    {
      "replicas": 1,
      "pool": {
        "zones": [
          "north"
        ],
        "slots_per_zone": 1
      }
    },
    {
      "replicas": 2,
      "pool": {
        "zones": [
          "north",
          "south"
        ],
        "slots_per_zone": 1
      }
    },
    {
      "replicas": 3,
      "pool": {
        "zones": [
          "north",
          "south"
        ],
        "slots_per_zone": 2
      }
    }
  ],
  "reject": [
    {
      "replicas": 4,
      "pool": {
        "zones": [
          "north",
          "south"
        ],
        "slots_per_zone": 4
      }
    },
    {
      "replicas": 2,
      "pool": {
        "zones": [],
        "slots_per_zone": 2
      }
    },
    {
      "replicas": 2,
      "pool": {
        "zones": [
          "north",
          "north"
        ],
        "slots_per_zone": 1
      }
    },
    {
      "replicas": 2,
      "pool": {
        "zones": [
          "north",
          "south"
        ],
        "slots_per_zone": 0.5
      }
    },
    {
      "replicas": 2,
      "pool": {
        "zones": [
          "north",
          "south"
        ],
        "slots_per_zone": 0
      }
    },
    {
      "replicas": 3,
      "pool": {
        "zones": [
          "north",
          "south"
        ],
        "slots_per_zone": 1
      }
    }
  ]
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
