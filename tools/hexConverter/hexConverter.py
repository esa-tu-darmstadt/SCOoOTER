import argparse
import math
import re


## Argument parsing
def auto_int(x):
	return int(x, 0)
parser = argparse.ArgumentParser(
	prog = 'hexConverter',
	description = 'Convert Verilog BRAM descriptions to BSV BRAM descriptions',
	epilog = 'Usage: hexConverter.py -o <path/to/output/dir> -a {32|64} -b <BRAM SIZE> <INPUT>')
parser.add_argument('input_file')
parser.add_argument('-o', '--output_prefix', required=True)
parser.add_argument('-b', '--bram_size', type=auto_int, required=True)
args = parser.parse_args()

for arch in [32, 64, 96, 128, 160, 192, 224, 256]:

	in_file = open(args.input_file, "rb")
	out_i = open(args.output_prefix + "_" + str(arch) + ".bsv", "w")
	out_d = open(args.output_prefix + "-data_" + str(arch) + ".bsv", "w")
	arch_byte = int(arch/8)

	## conversion helpers
	# Split list into chunks of n elements
	def chunk_list(lst, n):
		"""Yield successive n-sized chunks from lst."""
		def chunks_gen(lst, n):
			for i in range(0, len(lst), n):
				yield lst[i:i + n]
		return chunks_gen(lst, n)

	## chunk file
	chunks_text = []
	chunks_data = []
	
	# get text section
	chunk = in_file.read(arch_byte)
	while chunk:
		chunks_text.append(chunk)
		if(in_file.tell() >= args.bram_size):
			break
		chunk = in_file.read(arch_byte)

	while len(chunks_text)-1 <= args.bram_size/arch_byte:
		chunks_text.append(b'a'*arch_byte)
		
	# get data section
	in_file.seek(args.bram_size)
	chunk = in_file.read(arch_byte)
	while chunk:
		chunks_data.append(chunk)
		chunk = in_file.read(arch_byte)

	while len(chunks_data)-1 <= args.bram_size/arch_byte:
		chunks_data.append(b'a'*arch_byte)
	
	out_i.write("@0\n") # output new addr header
	out_d.write("@0\n") # output new addr header
	
	def write_to_file(chunks, out_file):
		for chunk in chunks:
			# split chunks into hex
			chunk_hex = [chunk.hex()[i:i+2] for i in range(0, len(chunk.hex()), 2)]
			chunks_inst = chunk_list(chunk_hex, int(arch/8)) # split byte array into words
			for inst in chunks_inst: # iterate over every word
				for byte in inst[-1::-1]: # reverse-iterate over every byte in said word
					# write output
					out_file.write(byte)
			out_file.write("\n")
			
	write_to_file(chunks_text, out_i)
	write_to_file(chunks_data, out_d)
	
	
	# create split SRAM description
	if arch == 32:
		for s in [0, 1]:
			out_b = open(args.output_prefix + "-data_" + str(arch) + "_" + str(s) + ".bsv", "w");
			out_b.write("@0\n") # output new addr header
			for chunk in chunks_data:
				chunk_hex = [chunk.hex()[i:i+2] for i in range(0, len(chunk.hex()), 2)]
				chunks_inst = chunk_list(chunk_hex, int(arch/8)) # split byte array into words
				for inst in chunks_inst:
					try:
						out_b.write(inst[2*s+1])
						out_b.write(inst[2*s  ])
					except:
						out_b.write("0000")
				out_b.write("\n")
		out_b.close()

	in_file.close()
	out_i.close()
	out_d.close()
