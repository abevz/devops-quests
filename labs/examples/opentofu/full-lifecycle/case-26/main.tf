terraform {
  required_version = ">= 1.5.0"
}

resource "terraform_data" "hook" {
  input = "created first"

  provisioner "local-exec" {
    command = "echo 'created ${self.id}' && exit 1"
  }
}
