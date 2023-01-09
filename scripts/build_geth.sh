#!/bin/bash
#
# Build Geth
#
set -e
set -u
set -o pipefail

. build_requirements.sh

S3_ARTIFACTS=$(aws s3 ls | grep eth-node | awk '{ print $3 }')
GETH_VERSION=v1.10.23-mev0.7.0
GETH_ARTIFACT=geth-$GETH_VERSION-$(uname -m).tar.gz

git clone https://github.com/flashbots/mev-geth.git
cd mev-geth
git checkout $GETH_VERSION

GO_VERSION=$(grep ^go go.mod | tr -d "go ")
goenv install $GO_VERSION
goenv local $(goenv versions | grep $GO_VERSION)

make geth

cd build/bin/
sha256sum geth > geth.sum
tar zcvf $GETH_ARTIFACT geth geth.sum

aws s3 cp $GETH_ARTIFACT s3://$S3_ARTIFACTS/
