#!/bin/bash
#
# Package requirements to build the binaries
#

apt-get update
apt-get install -y git wget curl xz-utils \
    gcc g++ mingw-w64 \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    cmake libssl-dev libxml2-dev vim apt-transport-https \
    zip unzip libtinfo5 patch zlib1g-dev autoconf libtool \
    pkg-config make gnupg2 libgmp-dev python3

#
# GoLang
#
if [[ ! -d ~/.goenv ]]; then
  git clone https://github.com/syndbg/goenv.git ~/.goenv
  echo 'export GOENV_ROOT="$HOME/.goenv"' >> ~/.bashrc
  echo 'export PATH="$GOENV_ROOT/bin:$PATH"' >> ~/.bashrc
  echo 'eval "$(goenv init -)"' >> ~/.bashrc
  echo 'export PATH="$GOROOT/bin:$PATH"' >> ~/.bashrc
  echo 'export PATH="$PATH:$GOPATH/bin"' >> ~/.bashrc
fi

. ~/.bashrc
