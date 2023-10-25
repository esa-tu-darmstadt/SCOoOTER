# Copyright 2022 Thales DIS design services SAS
#
# Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
# You may obtain a copy of the License at https://solderpad.org/licenses/
#
# Original Author: Zbigniew CHAMSKI (zbigniew.chamski@thalesgroup.fr)


noprint="-DHAS_PRINTF=0"


# where are the tools
if ! [ -n "$RISCV" ]; then
  echo "Error: RISCV variable undefined"
  return
fi

# install the required tools
source ./scoooter/regress/install-scoooter.sh
source ./scoooter/regress/install-riscv-dv.sh
source ./scoooter/regress/install-riscv-compliance.sh
source ./scoooter/regress/install-riscv-tests.sh

DV_SIMULATORS=spike,veri-testharness

cd scoooter/sim/

src0=../tests/custom/coremark/core_main.c
srcA=(
        ../tests/custom/coremark/uart.c
        ../tests/custom/coremark/core_list_join.c
        ../tests/custom/coremark/core_matrix.c
        ../tests/custom/coremark/core_portme.c
        ../tests/custom/coremark/core_state.c
        ../tests/custom/coremark/core_util.c
        ../tests/custom/common/syscalls.c
        ../tests/custom/common/crt.S
)

cflags_opt=(
        -O3 -g
        -fno-tree-loop-distribute-patterns
        -nostdlib
        -nostartfiles
        -lgcc
        $noprint
        -funroll-all-loops
        -ffunction-sections -fdata-sections
        -Wl,-gc-sections
        -falign-jumps=4 -falign-functions=16
)

cflags=(
        "${cflags_opt[@]}"
        "-DCOMPILER_FLAGS='\"${cflags_opt[*]}\"'"
        -DITERATIONS=2
        -DPERFORMANCE_RUN
        -DSKIP_TIME_CHECK
        -I../tests/custom/env
        -I../tests/custom/common
        -DNOPRINT
)

python3 cva6.py \
        --target hwconfig \
        --hwconfig_opts="--default_config=cv32a6_imac_sv0 --isa=rv32ima --NrLoadPipeRegs=0" \
        --iss="$DV_SIMULATORS" \
        --iss_yaml=cva6.yaml \
        --c_tests "$src0" \
        --gcc_opts="-lgcc -lm -O3 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -lgcc -lm ${srcA[*]} ${cflags[*]}" \
        --linker ../tests/custom/common/test.ld
        
cd -
