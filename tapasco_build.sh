#!/bin/bash

# add scoooter to bsvtools
git clone https://github.com/esa-tu-darmstadt/BSVTools.git
pushd core
../BSVTools/bsvAdd.py
popd

# terminate on error
set -e

# build SCOOOTER pe
pushd core
make SOC=1 SIM_TYPE=VERILOG ip
popd

# clean previous TaPaSCo builds and patch tapasco-riscv accordingly
pushd tools/tapasco-integration/tapasco-riscv/
make clean
patch -f -p1 < ../0001-add-SCOOOTER.patch || true
popd

# copy built SCOOOTER over
mkdir -p tools/tapasco-integration/tapasco-riscv/IP/riscv/scoooter/
cp -r core/build/ip/* tools/tapasco-integration/tapasco-riscv/IP/riscv/scoooter/

# build IP
pushd tools/tapasco-integration/tapasco-riscv/
make scoooter_pe
popd
