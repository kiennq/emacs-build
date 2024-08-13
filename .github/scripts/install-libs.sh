#!/bin/bash
mkdir -p ./git/mps
cd ./git/mps
git clone https://github.com/Ravenbrook/mps --branch release-1.118.0 --depth=1 .
git apply --ignore-space-change --ignore-whitespace ../../patches/mps/*.patch || true
PREFIX=${MSYSTEM-usr}
./configure --prefix=/$PREFIX
make quick VARIETY=hot && make install VARIETY=hot

ls -la /$PREFIX/include/mps*.h
