variable "replicas" {
  type    = number
  default = 2
}
check "spare_capacity" {
  assert {
    condition     = var.replicas >= 3
    error_message = "Less than three replicas: inspect capacity."
  }
}
