resource "terraform_data" "failure" {
  input = "demo"
  provisioner "local-exec" {
    command = "exit 7"
  }
}
