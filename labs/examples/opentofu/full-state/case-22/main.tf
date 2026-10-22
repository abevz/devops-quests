terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = ">= 2.5.0, < 3.0.0" }
  }
}
resource "local_file" "this" {
  filename = "${path.module}/demo.txt"
  content  = "desired"
  lifecycle { ignore_changes = [content] }
}
