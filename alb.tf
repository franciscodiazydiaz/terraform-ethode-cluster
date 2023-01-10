resource "aws_lb" "alb" {
  name            = local.name
  security_groups = [aws_security_group.alb.id]
  subnets         = module.vpc.public_subnets

  internal                         = false
  load_balancer_type               = "application"
  enable_cross_zone_load_balancing = "true"

  tags = local.tags
}

#
# Geth
#
resource "aws_lb_listener" "geth_8545" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8545
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.geth_8545.arn
  }
}

resource "aws_lb_target_group" "geth_8545" {
  name        = "${local.name}-geth"
  target_type = "instance"
  port        = 8545
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  health_check {
    #      healthy_threshold   = var.health_check["healthy_threshold"]
    #      interval            = var.health_check["interval"]
    #      unhealthy_threshold = var.health_check["unhealthy_threshold"]
    #      timeout             = var.health_check["timeout"]
    path = "/"
    port = 8545
  }
}

resource "aws_lb_target_group_attachment" "geth_8545" {
  count            = local.number_eth_nodes
  target_group_arn = aws_lb_target_group.geth_8545.arn
  target_id        = module.eth_node_instance[count.index].id
  port             = 8545
}

#
# Prio Load Balancer
#
resource "aws_lb_listener" "priolb_8080" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.priolb_8080.arn
  }
}

resource "aws_lb_target_group" "priolb_8080" {
  name        = local.prio_load_balancer_name
  target_type = "instance"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  health_check {
    #      healthy_threshold   = var.health_check["healthy_threshold"]
    #      interval            = var.health_check["interval"]
    #      unhealthy_threshold = var.health_check["unhealthy_threshold"]
    #      timeout             = var.health_check["timeout"]
    path = "/"
    port = 8080
  }
}

#
# Security Groups & Rules
#
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "SG for ALB"
  vpc_id      = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_security_group_rule" "alb_egress_wildcard" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow egress all TCP traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}
