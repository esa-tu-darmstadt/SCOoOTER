cd tools/core-v-verif

test_scripts=(dv-riscv-tests dv-riscv-arch-test dv-riscv-compliance dv-riscv-csr-access-test dv-generated-tests benchmark coremark)
mkdir -p core_v_logs

for script in ${test_scripts[@]}
do
	rm -rf scoooter/sim/out* &> /dev/null
	printf "$script "
	list_num=99 source ./scoooter/regress/$script.sh 2>&1 | tee >(grep -q "\[FAILED\]") >(grep -q -i "error") > core_v_logs/$script.log
	
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
