resource "terraform_data" "old" { input = "keep-identity" }
output "id" { value = terraform_data.old.id }
