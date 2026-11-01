terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
  default_tags {
    tags = {
      Project     = "filepipe"
      Environment = "dev"
      Owner       = var.owner
      CostCentre  = "learning"
      ManagedBy   = "terraform"
    }
  }
}

module "filepipe" {
  source = "../../modules/filepipe"

  environment        = "dev"
  vpc_cidr           = "10.2.0.0/16"
  admin_cidr         = var.admin_cidr
  ssh_public_key     = var.ssh_public_key
  alert_email        = var.alert_email
  log_retention_days = 14
}