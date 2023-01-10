locals {
  prio_load_balancer_name = "${local.name}-prio-lb"
}

module "prio_load_balancer" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.7.0"

  name = local.prio_load_balancer_name

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  health_check_type         = "EC2" # "ELB"
  health_check_grace_period	= 60

  vpc_zone_identifier = module.vpc.private_subnets

  # Launch template
  launch_template_use_name_prefix = true
  launch_template_name            = local.prio_load_balancer_name
  launch_template_description     = "Prio Load Balancer launch template"
  update_default_version          = true

  user_data = data.cloudinit_config.prio_load_balancer.rendered

  # FIXME: Using the same ImageId as the EthNode and the instance arch could be different
  image_id          = data.aws_ami.ubuntu.id
  instance_type     = "t4g.micro"
  ebs_optimized     = true
  enable_monitoring = true

  # IAM role & instance profile
  create_iam_instance_profile = true
  iam_role_use_name_prefix    = true
  iam_role_name               = local.prio_load_balancer_name
  iam_role_path               = "/ec2/"
  iam_role_description        = "Prio Load Balancer IAM Role"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  scaling_policies = {
    target_tracking_75 = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 75.0
      }
    }
  }

  security_groups	  = [aws_security_group.prio_load_balancer.id]
  target_group_arns	= [aws_lb_target_group.priolb_8080.arn]

  tags = local.tags
}

#
# User Data
#
data "cloudinit_config" "prio_load_balancer" {
  gzip          = false
  base64_encode = true

  # AWS cli
  part {
    content_type = "text/x-shellscript"
    content      = file("templates/eth_node_userdata_awscli.tftpl")
  }

  # prio-load-balancer
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/eth_node_userdata_priolb.tftpl", {
      s3_artifacts    = aws_s3_bucket.artifacts.id
      priolb_version  = "v0.4.0"
      priolb_parameters = [
        "-http=0.0.0.0:8080",
        "-redis=dev"
      ]
    })
  }

  # Fluent-bit
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/eth_node_userdata_fluentbit.tftpl", {
      aws_region = local.region
    })
  }
}

#
# Security Groups & Rules
#
resource "aws_security_group" "prio_load_balancer" {
  name        = local.prio_load_balancer_name
  description = "SG for the Prio Load Balancer"
  vpc_id      = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_security_group_rule" "prio_load_balancer_egress_tcp_wildcard" {
  security_group_id = aws_security_group.prio_load_balancer.id
  description       = "Allow egress all TCP traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "prio_load_balancer_ingress_alb" {
  security_group_id        = aws_security_group.prio_load_balancer.id
  description              = "Allow access to Geth from the ALB"
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

#
# IAM Policies
#
# TODO: The same policies are used for the ETH nodes
resource "aws_iam_role_policy" "prio_load_balancer_s3_artifacts" {
  name  = "${local.prio_load_balancer_name}-s3-artifacts"
  role  = module.prio_load_balancer.iam_role_name

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

resource "aws_iam_role_policy" "prio_load_balancer_cloudwatch_logs" {
  name  = "${local.prio_load_balancer_name}-cloudwatch-logs"
  role  = module.prio_load_balancer.iam_role_name

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
