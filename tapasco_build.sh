#!/bin/bash
set -e

# patch tapasco-riscv accordingly
pushd tools/tapasco-integration/tapasco-riscv/
patch -p1 < ../0001-add-SCOOOTER.patch
popd

# build SCOOOTER pe
pushd core
make SIM_TYPE=VERILOG ip
popd

# clean previous TaPaSCo builds
pushd tools/tapasco-integration/tapasco-riscv/
make clean
popd

# copy built SCOOOTER over
mkdir -p tools/tapasco-integration/tapasco-riscv/IP/riscv/scoooter/
cp -r core/build/ip/* tools/tapasco-integration/tapasco-riscv/IP/riscv/scoooter/

# build IP
pushd tools/tapasco-integration/tapasco-riscv/
make scoooter_pe
popd
