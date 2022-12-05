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
parser.add_argument('-a', '--arch', type=int, required=True)
parser.add_argument('-b', '--bram_size', type=auto_int, required=True)
args = parser.parse_args()

in_file = open(args.input_file, "r")
out_i = open(args.output_prefix + ".bsv.txt", "w")
out_d = open(args.output_prefix + "-data.bsv.txt", "w")

## conversion helpers
# Split list into chunks of n elements
def chunk_list(lst, n):
    """Yield successive n-sized chunks from lst."""
    def chunks_gen(lst, n):
        for i in range(0, len(lst), n):
            yield lst[i:i + n]
    return chunks_gen(lst, n)

# flag whether data or instructions are being parsed
datasection = False

## real conversion

# read file linewise
for line in in_file:

    # Address handling
    if line[0] == '@':
    	# extract segment addr
        addr = int(re.sub('@', '', line), base=16)
        # check if in dmem
        if addr >= args.bram_size:
            addr_s = addr-args.bram_size >> int(math.log2(args.arch/8)) # convert byte addr to word addr
            datasection = True # set section flag
            out_d.write(f"@{addr_s:x}\n") # output new addr header
        else: # if in imem
            addr_s = addr >> int(math.log2(args.arch/8)) # convert byte addr to word addr
            datasection = False # set section flag
            out_i.write(f"@{addr_s:x}\n") # output new addr header
    else: # data handling
        parts = line.split() # split string into distinct bytes
        chunks = chunk_list(parts, int(args.arch/8)) # split byte array into words
        for chunk in chunks: # iterate over every word
            for byte in chunk[-1::-1]: # reverse-iterate over every byte in said word
            	# write output
                if datasection:
                    out_d.write(byte)
                else:
                    out_i.write(byte)
            # write newline after word
            if datasection:
                out_d.write("\n")
            else:
                out_i.write("\n")

in_file.close()
out_i.close()
out_d.close()
