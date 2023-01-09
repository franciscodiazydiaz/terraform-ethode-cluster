# terraform-ethnode-cluster

Terraform code to deploy a Flashbots' Ethereum Node Cluster:

* Beacon Chain ([Prysm](https://github.com/flashbots/prysm))
* Execution Client ([Geth](https://github.com/flashbots/mev-geth))
* [Sync Proxy](https://github.com/flashbots/sync-proxy)
* [High/Low Prio Load Balancer](https://github.com/flashbots/prio-load-balancer)

## Requirements

* [Terraform 1.3.x]()
* [tfenv](https://github.com/kamatama41/tfenv) (Optional, Terraform version manager)

## Getting Started

Generate JWT Secret

```shell
echo "export JWTSECRET=$(openssl rand -hex 32 | tr -d /"\n/")" >> .env
source .env
```

Prepare the working directory to execute Terraform

```shell
terraform init
```

Create the infrastructure on AWS

```shell
terraform apply -var eth_node_jwtsecret=$JWTSECRET
```

Note: It is not recommended to store the tfstate file locally. You can keep it safely either using a module like [terraform-aws-tfstate-backend](https://github.com/cloudposse/terraform-aws-tfstate-backend) or [Terraform Cloud](https://cloud.hashicorp.com/products/terraform)
