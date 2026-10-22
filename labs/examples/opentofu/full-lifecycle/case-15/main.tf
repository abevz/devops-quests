variable "port" { default = 8080 }
resource "terraform_data" "app" {
  input = var.port
  lifecycle {
    precondition {
      condition     = var.port > 0
      error_message = "port must be positive."
    }
  }
}
