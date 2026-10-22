terraform {
  required_version = ">= 1.5.0"
}

variable "port" {
  type    = number
  default = 8080
}

resource "terraform_data" "service" {
  input = { port = var.port }

  lifecycle {
    precondition {
      condition     = var.port > 0
      error_message = "port must be greater than 0"
    }
    postcondition {
      condition     = self.output.port <= 65535
      error_message = "provider returned an invalid port"
    }
  }
}
