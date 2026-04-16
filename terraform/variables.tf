###############################################################################
# variables.tf – Assignment 15
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  description = "Resource name prefix (matches naming convention)"
  type        = string
  default     = "jhon-a15"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.15.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.15.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR"
  type        = string
  default     = "10.15.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "public_key_material" {
  description = "SSH public key content (paste your id_rsa.pub or id_ed25519.pub)"
  type        = string
  sensitive   = true
}

variable "trusted_cidr_blocks" {
  description = "Your IP(s) allowed to SSH to the public instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]   # NARROW THIS TO YOUR IP IN PRODUCTION
}

# VPC Flow Log custom format – captures all useful fields for analysis
variable "flow_log_format" {
  description = "VPC Flow Log record format"
  type        = string
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "Assignment-15"
    ManagedBy   = "Terraform"
    Batch       = "10.28"
    Student     = "Hector-Jonathan-Maldonado-Vega"
    Environment = "Training"
  }
}
