###############################################################################
# outputs.tf – Assignment 15
###############################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "public_ec2_public_ip" {
  description = "Public instance public IP – use this for SSH"
  value       = aws_instance.public.public_ip
}

output "public_ec2_private_ip" {
  description = "Public instance private IP"
  value       = aws_instance.public.private_ip
}

output "private_ec2_private_ip" {
  description = "Private instance private IP – SSH via bastion"
  value       = aws_instance.private.private_ip
}

output "flow_logs_s3_bucket" {
  description = "S3 bucket receiving VPC Flow Logs"
  value       = aws_s3_bucket.flow_logs.bucket
}

output "flow_logs_s3_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.flow_logs.arn
}

output "athena_results_bucket" {
  description = "Athena query results bucket"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.main.name
}

output "athena_database" {
  description = "Athena database name"
  value       = aws_athena_database.flow_logs.name
}

output "flow_log_id" {
  description = "VPC Flow Log resource ID"
  value       = aws_flow_log.main.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway Elastic IP (private subnet outbound traffic source)"
  value       = aws_eip.nat.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to public instance"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.public.public_ip}"
}

output "ssh_jump_to_private" {
  description = "SSH jump command to reach private instance via public bastion"
  value       = "ssh -J ec2-user@${aws_instance.public.public_ip} ec2-user@${aws_instance.private.private_ip}"
}

output "traffic_generation_commands" {
  description = "Commands to run for traffic generation"
  value = {
    ping_to_private  = "ping -c 20 ${aws_instance.private.private_ip}"
    wget_external    = "wget -q -O /dev/null https://www.amazon.com && echo done"
    blocked_port_test = "nc -zv ${aws_instance.private.private_ip} 443  # Will REJECT – port 443 not in SG"
    check_logs_in_s3 = "aws s3 ls s3://${aws_s3_bucket.flow_logs.bucket}/AWSLogs/ --recursive | head -20"
  }
}
