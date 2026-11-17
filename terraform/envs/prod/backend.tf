terraform {
  backend "s3" {
    bucket       = "filepipe-tfstate-213211871756" # from bootstrap output
    key          = "filepipe/prod/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # stops two people running apply at once
  }
}