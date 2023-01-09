#!/bin/bash
#
# Build Geth
#
set -e
set -u
set -o pipefail

. build_requirements.sh

S3_ARTIFACTS=$(aws s3 ls | grep eth-node | awk '{ print $3 }')
PRYSM_VERSION=develop-boost
PRYSM_ARTIFACT=prysm-$PRYSM_VERSION-$(uname -m).tar.gz

git clone https://github.com/flashbots/prysm.git
cd prysm
git checkout $PRYSM_VERSION

GO_VERSION=$(grep ^go go.mod | tr -d "go ")
goenv install -s $GO_VERSION
goenv local $(goenv versions | grep $GO_VERSION)
go install github.com/bazelbuild/bazelisk@latest

/root/go/$GO_VERSION*/bin/bazelisk build //cmd/beacon-chain:beacon-chain --config=release

cd bazel-bin/cmd/beacon-chain/beacon-chain_/
sha256sum beacon-chain > beacon-chain.sum
tar zcvf $PRYSM_ARTIFACT beacon-chain beacon-chain.sum

aws s3 cp $PRYSM_ARTIFACT s3://$S3_ARTIFACTS/
