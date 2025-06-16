import argparse
import shutil
import os

def main():

    # parse arguments
    parser = argparse.ArgumentParser(description="A script with --rootless flag.")
    parser.add_argument('--rootless', action='store_true', help='Enable rootless mode and copy files.')
    args = parser.parse_args()

    # setup rootless docker if needed
    if args.rootless:
        print("Setting up rootless Docker...")
        shutil.copy("Makefile_rootless", "caravel/Makefile")
        shutil.copy("Makefile_openlane_rootless", "caravel/openlane/Makefile")

    # copy EF_SRAM folder
    print("Creating EF_SRAM wrapper...")
    shutil.copytree("mkWrapWrapEfsRam", "caravel/openlane/mkWrapWrapEfsRam")

    # run initial setup
    print("Setting up Caravel...")
    os.system("cd caravel && make setup")

    # build EF_SRAM wrapper
    print("Build EF_SRAM wrapper...")
    os.system("cd caravel && make mkWrapWrapEfsRam")

    print("Done!")

if __name__ == "__main__":
    main()
