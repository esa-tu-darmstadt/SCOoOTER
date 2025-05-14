#!/usr/bin/python3

import os
import argparse
import sys
import json

def get_next_output_path(base_dir, prefix):
    # List all directories in the base directory
    existing_folders = [folder for folder in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, folder))]

    # Filter folders with the correct prefix
    prefixed_folders = [folder for folder in existing_folders if folder.startswith(prefix)]

    # Extract the numerical suffix and get the max number
    numbers = []
    for folder in prefixed_folders:
        try:
            # Extract the suffix (e.g., "prefix1" -> 1)
            num = int(folder[len(prefix):])
            numbers.append(num)
        except ValueError:
            # Ignore any folders that don't have a numeric suffix
            continue
    
    # Find the next number to use
    next_number = max(numbers, default=0) + 1
    
    # Construct the next output folder path
    next_folder = f"{prefix}{next_number}"
    next_path = os.path.join(base_dir, next_folder)

    return next_folder, next_path

parser = argparse.ArgumentParser(description="SCOoOTER Caravel build flow.")
    
parser.add_argument(
    'PERIOD', type=float, help="Frequency (numeric, nanoseconds)"
)
parser.add_argument(
    'UTIL', type=float, help="Utilization (numeric, fraction between 0 and 1)"
)
parser.add_argument(
    '--CARAVEL', action='store_true', help="Use Caravel Wrapper / Build entire SoC, not only Processor"
)
    
args = parser.parse_args()
period = args.PERIOD
util = args.UTIL

# check if SCOoOTER config is compatible
with open("core/src/Config.bsv", "r") as cfg:
    if args.CARAVEL and "typedef 1 IFUINST" not in cfg.read():
        print("Caravel wrapper currently only supports IFU width of 1. Please adapt your SCOoOTER config or build processor only.")

# create new output folder
outfolder, outpath = get_next_output_path("tools/openlane_asic/caravelscoooterdexie/openlane/", "mkScoooter")

# build core
os.system("cd core && make clean && CARAVEL=1 make EFSRAM=1 SIM_TYPE=VERILOG compile_top && cd ..")

# copy template to new out path
os.system(f"cp -r tools/openlane_asic/mkScoooter {outpath}")

# modify template config with passed values
topmodule = "mkScoooterCaravel" if args.CARAVEL else "mkDave"


with open(f"{outpath}/config.json", 'r') as f:
    data = json.load(f)

    # Update key values
    data['CLOCK_PERIOD'] = period
    data['FP_CORE_UTIL'] = util
    data['DESIGN_NAME'] = topmodule

    # Remove specified keys if not using CARAVEL
    if not args.CARAVEL:
        for key in ["VERILOG_FILES_BLACKBOX", "EXTRA_GDS_FILES", "EXTRA_LEFS", "EXTRA_LIBS", "EXTRA_SPEFS", "MACRO_PLACEMENT_CFG", "FP_PDN_MACRO_HOOKS"]:
            if key in data:
                del data[key]

    # Write back the modified JSON
    with open(f"{outpath}/config.json", 'w') as f:
        json.dump(data, f, indent=4)



# copy verilog files to new out path
os.system(f"cp core/build/verilog/*.v {outpath}/verilog/.")

# modify verilog file
os.system(f"sed -i 's/EF_SRAM_1024x32_wrapper/mkWrapWrapEfsRam/g' {outpath}/verilog/mkScoooterCaravel.v")

# copy scoooter config
os.system(f"cp core/src/Config.bsv {outpath}")

# run ol
os.system(f"cd tools/openlane_asic/caravelscoooterdexie && make {outfolder}")