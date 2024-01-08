# Copyright 2022 Thales DIS SAS
#
# Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
# You may obtain a copy of the License at https://solderpad.org/licenses/
#
# Original Author: Ayoub JALALI (ayoub.jalali@external.thalesgroup.com)

if ! [ -n "$RISCV" ]; then
  echo "Error: RISCV variable undefined"
  return
fi

# install the required tools
source ./scoooter/regress/install-scoooter.sh
source ./scoooter/regress/install-riscv-dv.sh
source ./scoooter/regress/install-spike.sh

if ! [ -n "$DV_TARGET" ]; then
  DV_TARGET=cv32a60x
fi

DV_SIMULATORS=vcs-uvm,spike

if ! [ -n "$list_num" ]; then
  list_num=2 #default test list
fi

export cov=0 #enable the Code Coverage

cd scoooter/sim/
dd=$(date '+%Y-%m-%d')
key_word="Mismatch[1]:"
#Read from the iss_regr.log to detect the failed tests
logfile=out_$dd/iss_regr.log
TESTLIST_FILE=cva6_base_testlist.yaml
DIRECTED_TESTLIST=../tests/testlist_isacov.yaml
j=0;
rm -rf out_$dd || true

if [[ "$list_num" = 1 ]];then
  TEST_NAME=(
           "riscv_arithmetic_basic_loop_test"
           "riscv_arithmetic_basic_test_no_comp"
           "riscv_arithmetic_basic_test_bcomp"
           "riscv_arithmetic_basic_illegal"
           "riscv_arithmetic_basic_test_comp"
           );
   I=(20 100 100 100 100);
elif [[ "$list_num" = 2 ]];then
  TEST_NAME=(
           "riscv_arithmetic_basic_same_reg_test"
           "riscv_arithmetic_basic_hazard_rdrs1_test"
           "riscv_arithmetic_basic_hazard_rdrs2_test"
           );
   I=(100 100 100);
elif [[ "$list_num" = 3 ]];then
  TEST_NAME=(
           "riscv_arithmetic_basic_csr_dummy"
           "riscv_arithmetic_basic_Randcsr_test"
           "riscv_arithmetic_basic_ebreak_dret_test"
           "riscv_arithmetic_basic_illegal_csr"
           );
   I=(20 20 20 20);
elif [[ "$list_num" = 4 ]];then
	TEST_NAME=(
           "riscv_mmu_stress_test"
           );
	I=(100);
elif [[ "$list_num" = 5 ]];then
  TEST_NAME=(
           "riscv_load_store_test"
           "riscv_load_store_cmp_test"
           "riscv_load_store_hazard_test"
           "riscv_unaligned_load_store_test"
           );
   I=(50 50 50 50);
elif [[ "$list_num" = 6 ]];then
	TEST_NAME=(
           "riscv_rand_jump_no_cmp_test"
           "riscv_rand_jump_illegal_test"
           "riscv_arithmetic_basic_sub_prog_test"
           );
	I=(75 50 20);
elif [[ "$list_num" = 7 ]];then
	TEST_NAME=(
           "cva6_instr_base_test"
           );
	I=(1);
elif [[ "$list_num" = 99 ]];then
  TEST_NAME=(
           "riscv_arithmetic_basic_loop_test"
           "riscv_arithmetic_basic_test_no_comp"
           "riscv_arithmetic_basic_test_bcomp"
           "riscv_arithmetic_basic_illegal"
           "riscv_arithmetic_basic_test_comp"
           "riscv_arithmetic_basic_same_reg_test"
           "riscv_arithmetic_basic_hazard_rdrs1_test"
           "riscv_arithmetic_basic_hazard_rdrs2_test"
           "riscv_arithmetic_basic_csr_dummy"
           "riscv_arithmetic_basic_Randcsr_test"
           "riscv_arithmetic_basic_ebreak_dret_test"
           "riscv_arithmetic_basic_illegal_csr"
           "riscv_mmu_stress_test"
           "riscv_load_store_test"
           "riscv_load_store_cmp_test"
           "riscv_load_store_hazard_test"
           "riscv_unaligned_load_store_test"
           "riscv_rand_jump_no_cmp_test"
           "riscv_rand_jump_illegal_test"
           "riscv_arithmetic_basic_sub_prog_test"
           "cva6_instr_base_test"
           );
   I=(20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 1);
elif [[ "$list_num" = 91 ]];then
  TEST_NAME=(
           "riscv_arithmetic_basic_loop_test"
           "riscv_arithmetic_basic_test_no_comp"
           "riscv_arithmetic_basic_test_bcomp"
           "riscv_arithmetic_basic_illegal"
           "riscv_arithmetic_basic_test_comp"
           );
   I=(20 20 20 20 20);
elif [[ "$list_num" = 92 ]];then
  TEST_NAME=(
           "riscv_arithmetic_basic_same_reg_test"
           "riscv_arithmetic_basic_hazard_rdrs1_test"
           "riscv_arithmetic_basic_hazard_rdrs2_test"
           );
   I=(20 20 20);
elif [[ "$list_num" = 94 ]];then
	TEST_NAME=(
           "riscv_mmu_stress_test"
           );
	I=(20);
elif [[ "$list_num" = 95 ]];then
  TEST_NAME=(
           "riscv_load_store_test"
           "riscv_load_store_cmp_test"
           "riscv_load_store_hazard_test"
           "riscv_unaligned_load_store_test"
           );
   I=(20 20 20 20);
elif [[ "$list_num" = 96 ]];then
	TEST_NAME=(
           "riscv_rand_jump_no_cmp_test"
           "riscv_rand_jump_illegal_test"
           "riscv_arithmetic_basic_sub_prog_test"
           );
	I=(20 20 20);
fi

if [[ "$list_num" != 0 ]];then
if [[ ${#TEST_NAME[@]} != ${#I[@]} ]];then
  echo "***********ERROR***************"
  echo "The length of TEST_NAME and Iteration should be equal !!!!"
  echo "Fix the length of one of the arrays"
  exit 
fi
printf "+====================================================================================+"
header="\n %-50s %-20s %s\n"
format=" %-50s %-20d %d\n"
printf "$header" "TEST NAME" "ITERATION" "BATCH SIZE"
printf "+====================================================================================+\n"

while [[ $j -lt ${#TEST_NAME[@]} ]];do
  printf "$format" \
  ${TEST_NAME[j]} ${I[j]} ${BZ[j]}
  j=$((j+1))
done
printf "+====================================================================================+\n"
j=0
while [[ $j -lt ${#TEST_NAME[@]} ]];do
  cp ../env/corev-dv/custom/riscv_custom_instr_enum.sv ./dv/src/isa/custom/
  python3 cva6.py --testlist=$TESTLIST_FILE --test ${TEST_NAME[j]} --iss_yaml cva6.yaml --target $DV_TARGET -cs ../env/corev-dv/target/rv32i/ --mabi ilp32 --isa rv32ima --simulator_yaml ../env/corev-dv/simulator.yaml --iss=spike,veri-testharness -i ${I[j]} -bz 1 --iss_timeout 6000
  n=0
  echo "Generate the test: ${TEST_NAME[j]}"
#this while loop detects the failed tests from the log file and remove them
  #echo "Deleting failed tests: "
  #while read line;do
  #  if [[ "$line" = "" ]];then
  #    n=$((n+1))
  #  fi
  #  for word in $line;do
  #    if [[ "$word" = "$key_word" ]];then
  #      echo -e ""${TEST_NAME[j+1]}"_"$n": Failed"
        #rm -rf vcs_results/default/vcs.d/simv.vdb/snps/coverage/db/testdata/"${TEST_NAME[j+1]}"_"$n"/
  #    fi
  #  done
  #done < $logfile
  rm -rf out_$dd || true
  j=$((j+1))
done
#Execute directed tests to improve functional coverage of ISA
j=0
elif [[ "$list_num" = 0 ]];then
   printf "==== Execute Directed tests to improve functional coverage of isa, by hitting corners !!! ====\n\n"
   python3 cva6.py --testlist=$DIRECTED_TESTLIST --iss_yaml cva6.yaml --target $DV_TARGET --iss=spike,veri-testharness
fi
cd -
