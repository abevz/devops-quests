terraform {
  required_version = ">= 1.7.0"
}

resource "terraform_data" "keep" {
  input = "leave-me"
}
