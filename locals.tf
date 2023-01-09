locals {
  region           = "us-east-2"
  azs              = ["${local.region}a", "${local.region}b", "${local.region}c"]
  name             = "${var.environment}-${var.project}"
  number_eth_nodes = var.number_eth_nodes > 0 ? var.number_eth_nodes : length(local.azs)

  tags = {
    environment = var.environment
    project     = var.project
  }
}
