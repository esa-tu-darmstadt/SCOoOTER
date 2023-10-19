. /opt/cad/mentor/2020-21/scripts/QUESTA-CORE-PRIME_2020.4_RHELx86.sh
export QUESTA_HOME=/opt/cad/mentor/2020-21/RHELx86/QUESTA-CORE-PRIME_2020.4/questasim/

cd tools/core-v-verif

export PROJECT_ROOT=$(pwd)
export ROOT_PROJECT=$(pwd)

export RISCV=/opt/riscv/
export RISCV_PREFIX=$RISCV/bin/riscv64-unknown-elf-
export RISCV_OBJCOPY=$RISCV/bin/riscv64-unknown-elf-objcopy
export RISCV_GCC=$RISCV/bin/riscv64-unknown-elf-gcc
export CV_SW_PREFIX=riscv64-unknown-elf-

export DV_TARGET=cv32a6_imac_sv0

test_scripts=(dv-riscv-tests dv-riscv-arch-test dv-riscv-compliance dv-riscv-csr-access-test dv-generated-tests benchmark coremark)
mkdir -p core-v-logs

for script in ${test_scripts[@]}
do
	rm -rf scoooter/sim/out* &> /dev/null
	printf "$script "
	list_num=99 source ./scoooter/regress/$script.sh 2>&1 | tee >(grep -q "\[FAILED\]") >(grep -q -i "error") > core-v-logs/$script.log
	
	if [ $? -eq 0 ] 
	then 
	  echo "PASS" 
	else 
	  echo "FAIL"
	fi
	mkdir -p core_v_logs/$script
	cp -r scoooter/sim/out* core_v_logs/$script/ &>/dev/null
done

cd -
