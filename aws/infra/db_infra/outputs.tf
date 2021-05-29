output "db_address" {
  description = "DB address"
  value       = aws_db_instance.psql.address
  sensitive   = false
}

output "db_username" {
  description = "DB user"
  value = aws_db_instance.psql.username
  sensitive = false
}

output "ec2_address" {
  description = "EC2 address"
  value = aws_instance.ec2-instance.public_dns
}

output "ec2_id" {
  description = "EC2 ID"
  value = aws_instance.ec2-instance.id
}

output "region" {
  description = "Region"
  value = var.region
}

output "db_pass" {
  description = "DB password"
  value = var.db_password
}
