variable "region" {
  description = "AWS region to build in"
  type        = string
  default     = "eu-west-2" # London
}

variable "owner" {
  description = "Your name or email, used in tags"
  type        = string
}

variable "github_repo" {
  description = "Your GitHub repo as owner/name, e.g. jsmith/filepipe"
  type        = string
}