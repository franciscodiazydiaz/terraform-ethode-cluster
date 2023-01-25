variable "environment" {
  type        = string
  description = "The name of the environment (dev, stage or prod)"
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "The environment name must be: dev, stage or prod"
  }
}

variable "project" {
  type        = string
  description = "The name of the project used as reference for tags, and resource names"
  default     = "eth-node-cluster"
}

variable "vpc_cidr_block" {
  type        = string
  description = "The IPv4 CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "number_eth_nodes" {
  type        = number
  description = "Number of Ethereum Nodes to spin up. If zero then it matches the number of AZs"
  default     = 0
}

variable "eth_node_ec2_key_name" {
  type        = string
  description = "Key name of the Key Pair to use for the EC2 instance. If empty it won't use an ssh key"
  default     = ""
}

variable "eth_node_jwtsecret" {
  description = "The JWT secret to use for authenticated RPC endpoints"
  type        = string
  sensitive   = true
}

variable "add_public_ip_alb" {
  description = "Whether to add a Security Group rule to the internet-facing ALB with the current public IP address"
  type        = bool
  default     = false
}

variable "enable_redis" {
  description = "Whether to provision ElastiCache Redis or not. If not, Prio-Load-Balancer will use its own Redis dev instance"
  type        = bool
  default     = false
}
