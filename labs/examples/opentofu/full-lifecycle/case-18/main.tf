variable "replicas" { default = 2 }
check "capacity" {
  assert {
    condition     = var.replicas >= 3
    error_message = "Need three replicas."
  }
}
