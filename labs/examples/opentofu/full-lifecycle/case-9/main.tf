variable "release" { default = "v1" }
resource "terraform_data" "app" {
  input = var.release
  lifecycle {
    ignore_changes = [input]
  }
}
