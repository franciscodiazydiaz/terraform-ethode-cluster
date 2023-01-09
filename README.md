# terraform-ethnode-cluster

Terraform code to deploy a Flashbots' Ethereum Node Cluster on
[Goerli testnet](https://github.com/eth-clients/goerli):

* Beacon Chain ([Prysm](https://github.com/flashbots/prysm))
* Execution Client ([Geth](https://github.com/flashbots/mev-geth))
* [Sync Proxy](https://github.com/flashbots/sync-proxy)
* [High/Low Prio Load Balancer](https://github.com/flashbots/prio-load-balancer)

## Requirements

* [Terraform 1.3.x](https://developer.hashicorp.com/terraform/downloads)
* [tfenv](https://github.com/kamatama41/tfenv) (Optional, Terraform version manager)
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html)

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

Note: It is not recommended to store the tfstate file locally. You can keep it safely
either using a module like [terraform-aws-tfstate-backend](https://github.com/cloudposse/terraform-aws-tfstate-backend) or [Terraform Cloud](https://cloud.hashicorp.com/products/terraform)

Once Terraform is executed for the first time:

1. Run [Geth](scripts/build_geth.sh) and [Prysm](scripts/build_prysm.sh) build scripts
2. Terminate and recreate the EC2 instances

Now, the EC2 instances should be able to fetch the archives from the S3 bucket.

## Terraform Role/User permissions

The following policies must be attached to the IAM Role or User that executes Terraform:

* AmazonEC2FullAccess
* AmazonSSMReadOnlyAccess
* IAMFullAccess
* AmazonVPCFullAccess
* AmazonS3FullAccess

## EC2 instance session and logs

To login to an EC2 instance [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) is in place, and either the web console or the awscli command can be used to access it.

[Fluent-bit](https://docs.fluentbit.io/manual/) is used to ship logs to CloudWatch inside
the log group `fluent-bit-cloudwatch`. Each service has its own log stream `from-fluent-bit-*`.
