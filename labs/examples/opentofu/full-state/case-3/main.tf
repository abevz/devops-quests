resource "terraform_data" "imported" {
  input = "ready"
}
import {
  to = terraform_data.imported
  id = "demo-local-id"
}
