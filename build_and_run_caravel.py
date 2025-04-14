#!/usr/bin/python3

import os

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


# create new output folder
outfolder, outpath = get_next_output_path("tools/openlane_asic/caravelscoooterdexie/openlane/", "mkScoooter")

# build core
os.system("cd core && make clean && CARAVEL=1 make EFSRAM=1 SIM_TYPE=VERILOG compile_top && cd ..")

# copy template to new out path
os.system(f"cp -r tools/openlane_asic/mkScoooter {outpath}")

# copy verilog files to new out path
os.system(f"cp core/build/verilog/*.v {outpath}/verilog/.")

# modify verilog file
os.system(f"sed -i 's/EF_SRAM_1024x32_wrapper/mkWrapWrapEfsRam/g' {outpath}/verilog/mkScoooterCaravel.v")

# copy scoooter config
os.system(f"cp core/src/Config.bsv {outpath}")

# run ol
os.system(f"cd tools/openlane_asic/caravelscoooterdexie && make {outfolder}")