module "redis" {
  source  = "cloudposse/elasticache-redis/aws"
  version = "0.49.0"

  name        = local.name
  environment = var.environment

  availability_zones = local.azs
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.private_subnets

  create_security_group      = true
  cluster_size               = 1
  instance_type              = "cache.t4g.small"
  apply_immediately          = true
  automatic_failover_enabled = false
  engine_version             = "6.x"
  family                     = "redis6.x"
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  parameter = []

  tags = local.tags
}

resource "aws_security_group_rule" "redis_ingress_prio_load_balancer" {
  security_group_id = module.redis.security_group_id
  description       = "Allow ingress traffic from prio-load-balancer"
  type              = "ingress"
  from_port         = module.redis.port
  to_port           = module.redis.port
  protocol          = "tcp"
  source_security_group_id = aws_security_group.prio_load_balancer.id
}
