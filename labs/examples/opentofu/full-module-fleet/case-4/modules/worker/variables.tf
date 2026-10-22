variable "name" {
  description = "Имя компонента"
  type        = string
  validation {
    condition     = length(var.name) >= 3
    error_message = "name must contain at least 3 characters."
  }
}
variable "settings" {
  description = "Настройки компонента"
  type        = object({ port = optional(number, 8080), labels = optional(map(string), {}) })
  default     = {}
}
variable "token" {
  description = "Учебный секрет"
  type        = string
  default     = "demo-token"
  sensitive   = true
}
