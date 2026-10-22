variable "name" { default = "default" }
resource "terraform_data" "this" { input = var.name }
output "name" { value = var.name }
