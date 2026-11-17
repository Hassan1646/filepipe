terraform {
  backend "s3" {
    bucket       = "REPLACE-WITH-YOUR-STATE-BUCKET" # from bootstrap output
    key          = "filepipe/prod/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # stops two people running apply at once
  }
}