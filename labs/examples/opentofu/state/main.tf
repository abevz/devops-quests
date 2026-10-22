terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
resource "local_file" "message" {
  filename = "${path.module}/managed.txt"
  content  = "declared\n"
}
output "path" { value = local_file.message.filename }
