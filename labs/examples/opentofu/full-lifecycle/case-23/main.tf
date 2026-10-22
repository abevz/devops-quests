variable "release" {
  type    = string
  default = "1.0"
}

resource "terraform_data" "release" {
  input = var.release
}

resource "terraform_data" "deployment" {
  input = "deploy"

  lifecycle {
    replace_triggered_by = [terraform_data.release]
  }
}
