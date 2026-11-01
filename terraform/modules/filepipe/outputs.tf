output "server_public_ip" {
  description = "Put this in the Ansible inventory"
  value       = aws_instance.server.public_ip
}

output "input_bucket" {
  value = aws_s3_bucket.data["input"].bucket
}

output "output_bucket" {
  value = aws_s3_bucket.data["output"].bucket
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}