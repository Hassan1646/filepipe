output "server_public_ip" {
  value = module.filepipe.server_public_ip
}

output "input_bucket" {
  value = module.filepipe.input_bucket
}

output "output_bucket" {
  value = module.filepipe.output_bucket
}

output "log_group" {
  value = module.filepipe.log_group
}