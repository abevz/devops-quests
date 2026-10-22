variable "release" {
  type    = string
  default = "v1"
}
resource "terraform_data" "app" {
  input = var.release
}
