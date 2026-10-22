terraform {
  required_providers {
    docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
    local  = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
