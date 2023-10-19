# Copyright 2022 Thales DIS design services SAS
#
# Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
# You may obtain a copy of the License at https://solderpad.org/licenses/
#
# Original Author: Guillaume Chauvon (guillaume.chauvon@thalesgroup.com)

# where are the tools
if [ -z "$RISCV" ]; then
  echo "Error: RISCV variable undefined"
  return
fi

# install the required tools
source ./scoooter/regress/install-scoooter.sh
source ./scoooter/regress/install-riscv-dv.sh

DV_SIMULATORS=spike,veri-testharness

if [ -z "$DV_TARGET" ]; then
  DV_TARGET=cv64a6_imafdc_sv39
fi

cd scoooter/sim/

BDIR=../tests/riscv-tests/benchmarks/
CVA6_FLAGS=""

GCC_COMMON_SRC=(
        ../tests/riscv-tests/benchmarks/common/syscalls.c
        ../tests/riscv-tests/benchmarks/common/crt.S
)

GCC_CFLAGS=(
        -lgcc
        -O3 --no-inline
        -I../tests/custom/env
        -I../tests/custom/common
        -DNOPRINT
        -march=rv32ima_zicsr
        -mabi=ilp32
)

GCC_OPTS="${GCC_CFLAGS[*]} ${GCC_COMMON_SRC[*]}"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/dhrystone/dhrystone.c   --gcc_opts="-L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S $BDIR/dhrystone/dhrystone_main.c -lgcc"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/median/median.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/median/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S $BDIR/median/median_main.c -lgcc"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/mm/mm.c   --gcc_opts="-lgcc -lm -O3 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/mm/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S $BDIR/mm/mm_main.c -lgcc -lm"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/mt-matmul/mt-matmul.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/mt-matmul/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S $BDIR/mt-matmul/matmul.c -lgcc"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/mt-vvadd/mt-vvadd.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/mt-vvadd/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S $BDIR/mt-vvadd/vvadd.c -lgcc -lm"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/multiply/multiply.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/multiply/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S $BDIR/multiply/multiply_main.c -lgcc -lm"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/qsort/qsort_main.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/qsort/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -lm"
 
python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/rsort/rsort.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/rsort/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -lm"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/spmv/spmv_main.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/spmv/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -lm"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/towers/towers_main.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/towers/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -lm"

python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml --linker=../tests/custom/common/test.ld --c_tests $BDIR/vvadd/vvadd_main.c   --gcc_opts="-O0 -L/scratch/ms/Toolchain_RV32_RV64/lib/gcc/riscv64-unknown-elf/12.2.0/rv32ima_zicsr_zifencei/ilp32 -L/scratch/ms/Toolchain_RV32_RV64/riscv64-unknown-elf/lib/rv32ima_zicsr_zifencei/ilp32 -I../tests/custom/env -I../tests/custom/common -I$BDIR/vvadd/ ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -lm"

cd -

