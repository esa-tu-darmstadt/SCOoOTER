#!/bin/python
import os

f_i = open("./core/build/konata.log", "r")
f_o = open("konata.log", "w")

f_o.write("Kanata 0004\nC=\t0\n")

cycle = 0
inc_id = {}
inc_cur = 0

for line in f_i:
	parts = line.split()
	if int(parts[0]) != cycle:
		diff = int(parts[0]) - cycle
		f_o.write(f"C\t{diff}\n")
		cycle = cycle + diff
	try:
		parts[2] = inc_id[parts[2]]
	except:
		inc_id[parts[2]] = str(inc_cur)
		parts[2] = str(inc_cur)
		inc_cur = inc_cur + 1
	f_o.write("\t".join(parts[1:5])+ " " + " ".join(parts[5::]) + "\n")
	
	
os.system("cat konata.log | spike-dasm > konata_dasm.log")
