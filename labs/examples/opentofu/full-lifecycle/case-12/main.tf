resource "terraform_data" "prepare" {
  input = "ready"
}
resource "terraform_data" "deploy" {
  input      = "app"
  depends_on = [terraform_data.prepare]
}
