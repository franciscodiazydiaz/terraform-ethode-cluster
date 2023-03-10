locals {
  # Changing instance type may affect the data device name mount-point, and
  # the processor architecture. (/dev/sdf, /dev/nvme1n1, /dev/xvdf)
  eth_node_instance_type    = "m6g.large" # ARM (Nitro instance) / NVMe
  eth_node_instance_arch    = endswith(split(".", local.eth_node_instance_type)[0], "g") ? "arm64" : "amd64"
  eth_node_data_device_name = "/dev/sdf"
}

module "eth_node_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 4.3"

  for_each = { for n in range(local.number_eth_nodes) : n => local.azs[n] }

  name = "${local.name}-eth-node-${each.key}"

  ami           = data.aws_ami.ubuntu.id
  instance_type = local.eth_node_instance_type

  availability_zone      = each.value
  key_name               = var.eth_node_ec2_key_name
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.eth_node.id]
  subnet_id              = module.vpc.private_subnets[each.key]
  user_data              = data.cloudinit_config.eth_node_instance.rendered

  root_block_device = [{
    volume_size = 20
    volume_type = "gp3"
  }]

  ebs_block_device = [{
    device_name = local.eth_node_data_device_name
    volume_size = 500
    volume_type = "gp3"
  }]

  create_iam_instance_profile = true

  tags = local.tags
}

#
# User Data
#
data "cloudinit_config" "eth_node_instance" {
  gzip          = false
  base64_encode = false

  # EBS data volume
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/userdata_ebs.tftpl", {
      data_device_name = local.eth_node_data_device_name,
      data_mount_path  = "/data"
    })
  }

  # AWS cli
  part {
    content_type = "text/x-shellscript"
    content      = file("templates/userdata_awscli.tftpl")
  }

  # Geth
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/userdata_geth.tftpl", {
      data_mount_path = "/data"
      s3_artifacts    = aws_s3_bucket.artifacts.id
      jwtsecret       = var.eth_node_jwtsecret
      geth_version    = "v1.10.23-mev0.7.0"
      geth_parameters = [
        "--goerli",
        "--http",
        "--http.api=engine,eth,web3,net,debug",
        "--http.addr=0.0.0.0",
        "--http.vhosts=*",
        "--authrpc.vhosts=*",
        "--authrpc.addr=0.0.0.0",
        "--authrpc.jwtsecret=$DATADIR/jwtsecret",
        "--datadir=$DATADIR",
        "--metrics",
        "--metrics.addr=0.0.0.0",
        "--log.json",
        "--syncmode=full",
        "--verbosity=3",
      ]
    })
  }

  # Prysm
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/userdata_prysm.tftpl", {
      data_mount_path = "/data"
      s3_artifacts    = aws_s3_bucket.artifacts.id
      jwtsecret       = var.eth_node_jwtsecret
      prysm_version   = "develop-boost"
      prysm_parameters = [
        "--prater",
        "--accept-terms-of-use",
        "--datadir=$DATADIR/beacondata",
        "--execution-endpoint=http://localhost:8551",
        "--genesis-state=$DATADIR/genesis.ssz",
        "--jwt-secret=$DATADIR/jwtsecret",
        "--log-format=json",
        "--monitoring-host=0.0.0.0",
        "--checkpoint-sync-url=https://goerli.beaconstate.ethstaker.cc",
        "--genesis-beacon-api-url=https://goerli.beaconstate.ethstaker.cc",
      ]
    })
  }

  # Fluent-bit
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/userdata_fluentbit.tftpl", {
      aws_region = local.region
    })
  }
}

#
# AMI: Ubuntu 22.04
#
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-${local.eth_node_instance_arch}-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

#
# Security Groups & Rules
#
resource "aws_security_group" "eth_node" {
  name        = "${local.name}-eth-node"
  description = "SG for the Ethereum Nodes"
  vpc_id      = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_security_group_rule" "eth_node_egress_tcp_wildcard" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow egress all TCP traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_egress_udp_wildcard" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow egress all UDP traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_ingress_geth_alb" {
  security_group_id        = aws_security_group.eth_node.id
  description              = "Allow access to Geth from the ALB"
  type                     = "ingress"
  from_port                = 8545
  to_port                  = 8545
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "eth_node_ingress_self_geth" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow access to Geth between Ethereum Nodes running Geth"
  type              = "ingress"
  from_port         = 8545
  to_port           = 8545
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "eth_node_ingress_geth_tcp_p2p" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow TCP P2P access to Geth"
  type              = "ingress"
  from_port         = 30303
  to_port           = 30303
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_ingress_geth_udp_p2p" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow UDP P2P access to Geth"
  type              = "ingress"
  from_port         = 30303
  to_port           = 30303
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_ingress_prysm_tcp_p2p" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow TCP P2P access to Prysm"
  type              = "ingress"
  from_port         = 13000
  to_port           = 13000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_ingress_prysm_udp_p2p" {
  security_group_id = aws_security_group.eth_node.id
  description       = "Allow UDP P2P access to Prysm"
  type              = "ingress"
  from_port         = 12000
  to_port           = 12000
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_ingress_priolb" {
  security_group_id        = aws_security_group.eth_node.id
  description              = "Allow access to Geth from the prio-load-balancer"
  type                     = "ingress"
  from_port                = 8545
  to_port                  = 8545
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.prio_load_balancer.id
}

#
# IAM Policies
#
# TODO: The EC2 instances should use the same IAM Role, instead of one per instance.
resource "aws_iam_role_policy_attachment" "eth_node_ssm_managed_policy" {
  count      = local.number_eth_nodes
  role       = module.eth_node_instance[count.index].iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "eth_node_s3_artifacts" {
  count = local.number_eth_nodes
  name  = "${local.name}-eth-node-s3-artifacts"
  role  = module.eth_node_instance[count.index].iam_role_name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${aws_s3_bucket.artifacts.id}"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::${aws_s3_bucket.artifacts.id}/*"]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "eth_node_cloudwatch_logs" {
  count = local.number_eth_nodes
  name  = "${local.name}-eth-node-cloudwatch-logs"
  role  = module.eth_node_instance[count.index].iam_role_name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents"
    ],
    "Resource": "*"
  }]
}
EOF
}
