# main.tf
terraform {
  required_version = ">= 1.7.0"
}

resource "terraform_data" "example" {
  input = "imported-lab-object"
}
