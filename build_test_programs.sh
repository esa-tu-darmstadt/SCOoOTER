#!/bin/bash

git clone https://github.com/esa-tu-darmstadt/BSVTools.git
set -e

pushd core
../BSVTools/bsvAdd.py
popd

# Build ISA testbench
pushd tools/riscv-tests
git submodule update --init --recursive
cp -r ../riscv-tests-override/* .
ls
./configure
make install BUS=128
popd

# Build embench
pushd tools/embench
pushd embench-iot
git reset --hard HEAD
popd
make patch
make
make install
popd

# build priv tests
pushd tools/riscv-arch-tests
make install
popd

# build amo tests
export PATH="/opt/cad/mentor/2020-21/RHELx86/QUESTA-CORE-PRIME_2020.4/questasim/bin:${PATH}"
export MGLS_LICENSE_FILE=/opt/cad/keys/mentor
pip install --user cocotb-bus cocotb
pushd tools/riscv-dv
export PATH=$HOME/.local/bin/:$PATH  # add ~/.local/bin to the $PATH (only once)
pip3 install --user -e .
popd
pushd tools/riscv-dv-build
make install
popd

# build custom stuff
pushd tools/customTests
make
make install
popd

