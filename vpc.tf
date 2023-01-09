module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.18.1"

  name = local.name

  cidr = var.vpc_cidr_block
  azs  = local.azs

  private_subnets = [for n in range(length(local.azs)) : cidrsubnet(var.vpc_cidr_block, 8, n)]       # 10.0.x.0/24
  public_subnets  = [for n in range(length(local.azs)) : cidrsubnet(var.vpc_cidr_block, 8, 100 + n)] # 10.0.10x.0/24

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment == "dev" ? true : false
  one_nat_gateway_per_az = false

  # Required by the EC2 VPC Endpoint
  enable_dns_hostnames = true
  enable_dns_support   = true
  #enable_dhcp_options              = true

  tags = local.tags
}

#
# VPC Endpoints
#
module "endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [data.aws_security_group.default.id]

  endpoints = {
    s3 = {
      service = "s3"
      tags    = { Name = "s3-vpc-endpoint" }
    },
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_ingress_tls.id]
    },
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_ingress_tls.id]
    },
    ec2 = {
      service             = "ec2"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_ingress_tls.id]
    },
    kms = {
      service             = "kms"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_ingress_tls.id]
    }
  }
}

#
# VPC Security Groups
#
data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "vpc_ingress_tls" {
  name_prefix = "${local.name}-vpc-ingress-tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = local.tags
}
