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
  health_check_grace_period = 60

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

  security_groups   = [aws_security_group.prio_load_balancer.id]
  target_group_arns = [aws_lb_target_group.priolb_8080.arn]

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
    content      = file("templates/userdata_awscli.tftpl")
  }

  # prio-load-balancer
  part {
    content_type = "text/x-shellscript"
    content = templatefile("templates/userdata_priolb.tftpl", {
      s3_artifacts   = aws_s3_bucket.artifacts.id
      priolb_version = "v0.4.0"
      priolb_parameters = [
        "-http=0.0.0.0:8080",
        "-redis=${var.enable_redis ? "${module.redis[0].endpoint}:${module.redis[0].port}" : "dev"}",
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
  description              = "Allow access to priolb from the ALB"
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
  name = "${local.prio_load_balancer_name}-s3-artifacts"
  role = module.prio_load_balancer.iam_role_name

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
  name = "${local.prio_load_balancer_name}-cloudwatch-logs"
  role = module.prio_load_balancer.iam_role_name

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

#
# Lambda to manage "Execution Nodes" in the Prio Load Balancer
#
module "lambda_function_in_vpc" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${local.name}-manage-priolb-nodes"
  description   = "Manage Prio Load Balancer Execution Nodes"
  handler       = "main.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  source_path = "lambda/manage-priolb-nodes"

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.prio_load_balancer_lambda.id]
  attach_network_policy  = true

  create_role = true

  attach_policy_statements = true
  policy_statements = {
    ec2_describe = {
      effect    = "Allow",
      actions   = ["ec2:DescribeInstances"],
      resources = ["*"]
    }
  }

  # Read FAQ: https://github.com/terraform-aws-modules/terraform-aws-lambda
  create_current_version_allowed_triggers = false
  allowed_triggers = {
    EventBridge = {
      principal  = "events.amazonaws.com"
      source_arn = module.eventbridge.eventbridge_rule_arns["ec2_state_change"]
    }
  }

  environment_variables = {
    PRIOLB_ENDPOINT = "http://${aws_lb.alb.dns_name}:8080/nodes"
  }

}

resource "aws_security_group" "prio_load_balancer_lambda" {
  name        = "${local.prio_load_balancer_name}-lambda"
  description = "SG for the Prio Load Balancer Lambda"
  vpc_id      = module.vpc.vpc_id

  tags = local.tags
}

# FIXME: The lambda functions needs to reach the priolb, and they are all behind the ALB
#        The `source_security_group` cannot be used as the ALB is public
resource "aws_security_group_rule" "alb_ingress_8080_anywhere" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow ingress traffic to ALB 8080 from anywhere"
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "prio_load_balancer_lambda_egress_tcp_wildcard" {
  security_group_id = aws_security_group.prio_load_balancer_lambda.id
  description       = "Allow egress all TCP traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eth_node_ingress_priolb_lambda" {
  security_group_id        = aws_security_group.eth_node.id
  description              = "Allow ingress traffic to Geth from the priolb Lambda function"
  type                     = "ingress"
  from_port                = 8545
  to_port                  = 8545
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.prio_load_balancer_lambda.id
}

#
# EventBridge
#
module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"

  # Looks like some targets are only working with the default bus
  # bus_name = "${local.name}-priolb"
  create_bus = false

  create_permissions   = true
  attach_lambda_policy = true
  lambda_target_arns   = [module.lambda_function_in_vpc.lambda_function_arn]

  rules = {
    ec2_state_change = {
      enabled     = true
      description = "EC2 Instance State-change Notification"
      event_pattern = jsonencode({
        "source" : ["aws.ec2"],
        "detail-type" : ["EC2 Instance State-change Notification"],
        "detail" : {
          "state" : ["running", "shutting-down", "stopping"],
          "instance-id" : [for instance in module.eth_node_instance : instance.id]
        }
      })
    }
  }

  targets = {
    ec2_state_change = [{
      name = "Manage Prio Load Balancer Nodes"
      arn  = module.lambda_function_in_vpc.lambda_function_arn
    }]
  }

  tags = local.tags
}

