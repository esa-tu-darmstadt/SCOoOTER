
all: patch bin collect

patch:
	cp -r overlay/* riscv-arch-test

bin: patch
	cd riscv-arch-test && RISCV_TARGET=tapasco RISCV_DEVICE=privilege make clean && RISCV_TARGET=tapasco RISCV_DEVICE=privilege make build

clean:
	cd riscv-arch-test RISCV_TARGET=tapasco RISCV_DEVICE=privilege clean
	rm -rf out

collect: bin
	mkdir -p out/elf
	cp riscv-arch-test/work/rv32i_m/privilege/*.elf out/elf/

transform: collect
	#copy all binaries over
	@$(eval ELFS:=$(wildcard out/elf/*))
	@$(eval ELFS_SHORT := $(basename $(notdir ${ELFS})))

	#make binaries from ELF files
	@mkdir -p out/bin
	@$(foreach bin, ${ELFS_SHORT}, riscv64-unknown-elf-objcopy -O binary out/elf/$(bin).elf out/bin/$(bin).bin ; )

	#make BSV hex from verilog
	@mkdir -p out/bsv_hex
	@$(foreach bin, ${ELFS_SHORT}, python3 ../hexConverter/hexConverter.py out/bin/$(bin).bin -o out/bsv_hex/$(bin) -b 0x10000 ; )
	
	#make dump from ELF files
	@mkdir -p out/dump
	@$(foreach bin, ${ELFS_SHORT}, riscv64-unknown-elf-objdump -d out/elf/$(bin).elf > out/dump/$(bin).dump ; )

install: transform
	@mkdir -p ../../testPrograms/priv
	@cp -r out/* ../../testPrograms/priv
