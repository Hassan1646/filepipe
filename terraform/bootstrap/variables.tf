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
  description = "GitHub repo as it appears in the OIDC sub claim: owner/name or owner@id/name@id"
  type        = string
}