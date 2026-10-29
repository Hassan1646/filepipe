output "state_bucket" {
  description = "Put this in each environment's backend.tf"
  value       = aws_s3_bucket.state.bucket
}

output "ecr_repository_url" {
  description = "Where Docker images are pushed"
  value       = aws_ecr_repository.filepipe.repository_url
}

output "github_ci_role_arn" {
  description = "Add this to GitHub as the AWS_ROLE_ARN secret"
  value       = aws_iam_role.github_ci.arn
}