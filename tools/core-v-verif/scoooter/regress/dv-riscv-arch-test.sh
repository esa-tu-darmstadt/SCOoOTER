# Copyright 2021 Thales DIS design services SAS
#
# Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
# You may obtain a copy of the License at https://solderpad.org/licenses/
#
# Original Author: Jean-Roch COULON - Thales

# where are the tools
if ! [ -n "$RISCV" ]; then
  echo "Error: RISCV variable undefined"
  return
fi

# install the required tools
source ./scoooter/regress/install-scoooter.sh
source ./scoooter/regress/install-riscv-dv.sh
source ./scoooter/regress/install-riscv-arch-test.sh

mkdir -p $ROOT_PROJECT/scoooter/tests/riscv-arch-test/riscv-target
cp $ROOT_PROJECT/vendor/riscv/riscv-isa-sim/arch_test_target/spike $ROOT_PROJECT/scoooter/tests/riscv-arch-test/riscv-target -r

if ! [ -n "$DV_TARGET" ]; then
  DV_TARGET=cv64a6_imafdc_sv39
fi

DV_SIMULATORS=veri-testharness,spike

cd scoooter/sim
python3 cva6.py --testlist=../tests/testlist_riscv-arch-test.yaml --target $DV_TARGET --iss_yaml=cva6.yaml --iss=$DV_SIMULATORS $DV_OPTS --linker=../tests/riscv-arch-test/riscv-target/spike/link.ld
cd -
