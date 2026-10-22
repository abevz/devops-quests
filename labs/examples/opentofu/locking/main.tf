resource "terraform_data" "slow" {
  provisioner "local-exec" {
    command = "printf ready > lock-ready; sleep 8"
  }
}
