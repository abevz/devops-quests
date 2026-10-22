variable "release" { default = "v1" }
resource "terraform_data" "app" {
  input            = var.release
  triggers_replace = [var.release]
  lifecycle { create_before_destroy = true }
}
