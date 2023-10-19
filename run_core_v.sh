cd tools/core-v-verif
setopt +o nomatch

test_scripts=(dv-generated-tests dv-riscv-csr-access-test benchmark coremark dhrystone dv-riscv-arch-test dv-riscv-compliance dv-riscv-tests)
mkdir -p core_v_logs

for script in ${test_scripts[@]}
do
	rm -rf scoooter/sim/out* &> /dev/null
	printf "$script "
	list_num=99 source ./scoooter/regress/$script.sh 2>&1 | tee >(grep -q "\[FAILED\]") > core_v_logs/$script.log
	
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
