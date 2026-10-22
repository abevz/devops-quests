variable "name" {
  type = string
  validation {
    condition     = length(var.name) > 0
    error_message = "Name cannot be empty."
  }
}
