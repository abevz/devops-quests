terraform {
  required_version = ">= 1.5.0"
}

resource "terraform_data" "prepare" {
  input = "prepare first"
}

resource "terraform_data" "deploy" {
  input      = "deploy second"
  depends_on = [terraform_data.prepare]
}
