. /opt/cad/mentor/2020-21/scripts/QUESTA-CORE-PRIME_2020.4_RHELx86.sh
export QUESTA_HOME=/opt/cad/mentor/2020-21/RHELx86/QUESTA-CORE-PRIME_2020.4/questasim/

cd tools/core-v-verif

export PROJECT_ROOT=$(pwd)
export ROOT_PROJECT=$(pwd)

export RISCV_PREFIX=$RISCV/bin/riscv64-unknown-elf-
export RISCV_OBJCOPY=$RISCV/bin/riscv64-unknown-elf-objcopy
export RISCV_GCC=$RISCV/bin/riscv64-unknown-elf-gcc
export CV_SW_PREFIX=riscv64-unknown-elf-

export DV_TARGET=cv32a6_imac_sv0

test_scripts=(dv-riscv-tests dv-riscv-arch-test dv-riscv-compliance dv-riscv-csr-access-test dv-generated-tests dv-generated-tests dv-generated-tests dv-generated-tests dv-generated-tests dv-generated-tests dv-generated-tests benchmark coremark)
test_list_no=(             0                  0                   0                        0                 91                 92                  3                 94                 95                 96                  7         0        0)
mkdir -p core-v-logs

source ./scoooter/regress/install-spike.sh

for i in ${!test_scripts[@]}
do
	rm -rf scoooter/sim/out* &> /dev/null
	printf "${test_scripts[i]} "
	list_num=${test_list_no[i]} source ./scoooter/regress/${test_scripts[i]}.sh 2>&1 | tee >(grep -q "\[FAILED\]") >(grep -q -i "error") > core-v-logs/${test_scripts[i]}_${test_list_no[i]}.log
	
	if [ $? -eq 0 ] 
	then 
	  echo "PASS" 
	else 
	  echo "FAIL"
	fi
done

cd -
