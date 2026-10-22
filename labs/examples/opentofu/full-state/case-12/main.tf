# новая main.tf после рефакторинга
terraform {
  required_version = ">= 1.7.0"
}

resource "terraform_data" "renamed" {
  input = "stable"
}

moved {
  from = terraform_data.original
  to   = terraform_data.renamed
}
