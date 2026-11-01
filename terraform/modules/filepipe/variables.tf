variable "environment" {
  description = "dev, test or prod"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "vpc_cidr" {
  description = "IP range for this environment's network"
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP with /32, e.g. 81.2.69.160/32"
  type        = string
}

variable "ssh_public_key" {
  description = "Contents of your ~/.ssh/filepipe.pub"
  type        = string
}

variable "instance_type" {
  description = "Server size"
  type        = string
  default     = "t3.micro"
}

variable "alert_email" {
  description = "Where failure alerts are sent"
  type        = string
}

variable "log_retention_days" {
  description = "How long to keep logs"
  type        = number
  default     = 14
}