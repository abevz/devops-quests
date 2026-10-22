terraform {
  required_version = ">= 1.5.0"
}

variable "release" {
  type    = string
  default = "v1"
}

resource "terraform_data" "database" {
  input            = "keep"
  triggers_replace = [var.release]

  lifecycle {
    prevent_destroy = true
  }
}
