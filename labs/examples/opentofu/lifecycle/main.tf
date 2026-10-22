variable "release_value" { default = "v1" }
resource "terraform_data" "release" {
  input            = var.release_value
  triggers_replace = [var.release_value]
  lifecycle { create_before_destroy = true }
}
output "id" { value = terraform_data.release.id }
