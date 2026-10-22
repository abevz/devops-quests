variable "release" { default = "v1" }
resource "terraform_data" "version" { input = var.release }
resource "terraform_data" "app" {
  input = "app"
  lifecycle {
    replace_triggered_by = [terraform_data.version]
  }
}
