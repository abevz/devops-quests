resource "terraform_data" "this" {
  input = { name = var.name, port = var.settings.port, labels = var.settings.labels }
}
