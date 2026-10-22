variable "name" { type = string }
output "label" { value = "${var.name}-dev" }
