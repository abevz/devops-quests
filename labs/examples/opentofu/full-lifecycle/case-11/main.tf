terraform {
  required_version = ">= 1.5.0"
}

resource "terraform_data" "app" {
  input = "v2"

  lifecycle {
    ignore_changes = [input]
  }
}
