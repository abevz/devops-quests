resource "terraform_data" "new" {
  input = "stable"
}
moved {
  from = terraform_data.old
  to   = terraform_data.new
}
