variable "release" { default = "v1" }
resource "terraform_data" "app" {
  input = var.release
}
output "release" {
  value = terraform_data.app.output
}
