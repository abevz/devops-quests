resource "terraform_data" "item" {
  input = "tracked"
}
output "value" {
  value = terraform_data.item.output
}
