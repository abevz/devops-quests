output "name" {
  description = "Имя компонента после применения"
  value       = terraform_data.this.output.name
}
output "id" {
  description = "Идентификатор компонента"
  value       = terraform_data.this.id
}
output "token" {
  description = "Учебный секрет для родителя"
  value       = var.token
  sensitive   = true
}
