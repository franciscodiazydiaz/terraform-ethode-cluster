#!/bin/bash
#
# Build prio-load-balancer
#
set -e
set -u
set -o pipefail

. build_requirements.sh

S3_ARTIFACTS=$(aws s3 ls | grep eth-node | awk '{ print $3 }')
PRIOLB_VERSION=v0.4.0
PRIOLB_ARTIFACT=prio-load-balancer-$PRIOLB_VERSION-$(uname -m).tar.gz

git clone https://github.com/flashbots/prio-load-balancer.git
cd prio-load-balancer
git checkout $PRIOLB_VERSION

GO_VERSION=$(grep ^go go.mod | tr -d "go ")
goenv install -s $GO_VERSION
goenv local $(goenv versions | grep $GO_VERSION)

make build

sha256sum prio-load-balancer > prio-load-balancer.sum
tar zcvf $PRIOLB_ARTIFACT prio-load-balancer prio-load-balancer.sum

aws s3 cp $PRIOLB_ARTIFACT s3://$S3_ARTIFACTS/
