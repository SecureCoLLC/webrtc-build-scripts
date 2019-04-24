#!/usr/bin/env bash

sudo apt-get -y install\
	git\
	python

if [[ ! -d depot_tools ]]
then
	git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

export PATH=$PATH:`pwd`/depot_tools

pushd /vagrant
sudo mkdir -p build_webrtc
sudo chown vagrant build_webrtc
pushd build_webrtc

export DEFAULT_WEBRTC_URL="https://chromium.googlesource.com/external/webrtc.git"

if [[ ! -d src ]]
then
	gclient config --name=src "$DEFAULT_WEBRTC_URL"
	gclient sync --nohooks --no-history

	./src/build/install-build-deps.sh --unsupported --no-syms --no-arm --no-chromeos-fonts --no-nacl
	gclient runhooks
fi
