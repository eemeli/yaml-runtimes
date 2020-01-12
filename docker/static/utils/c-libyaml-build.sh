#!/bin/sh

set -x
cd /tmp
cp $SOURCE .
tar xvf yaml-$VERSION.tar.gz
cd yaml-$VERSION
./configure --prefix /build
make LDFLAGS="$LDFLAGS -static"
make
make test
make install
mkdir -p /build/bin
cp tests/run-parser-test-suite /build/bin/libyaml-parser
cp tests/run-emitter-test-suite /build/bin/libyaml-emitter
