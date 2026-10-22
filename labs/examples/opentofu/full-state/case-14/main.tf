terraform {
  required_version = ">= 1.7.0"
}

removed {
  from = terraform_data.keep
  lifecycle {
    destroy = false
  }
}
