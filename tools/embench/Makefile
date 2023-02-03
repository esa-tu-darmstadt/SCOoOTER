 # 
 # Copyright (c) 2019-2020 Embedded Systems and Applications, TU Darmstadt.
 # This file is part of RT-LIFE
 # (see https://github.com/esa-tu-darmstadt/RT-LIFE).
 #
 # Permission is hereby granted, free of charge, to any person obtaining
 # a copy of this software and associated documentation files (the "Software"),
 # to deal in the Software without restriction, including without limitation
 # the rights to use, copy, modify, merge, publish, distribute, sublicense,
 # and/or sell copies of the Software, and to permit persons to whom the
 # Software is furnished to do so, subject to the following conditions:
 #
 # The above copyright notice and this permission notice shall be included
 # in all copies or substantial portions of the Software.
 #
 # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 # THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 # THE SOFTWARE.
 #

CROSS_COMPILE?="riscv64-unknown-elf"

TARGETS = $(subst /,, $(filter %/, $(wildcard en_*/)))
all: clean build collect collect_binaries install

.PHONY: patch
patch: embench-iot
	cd embench-iot && patch -p1 < ../0001-change-local-factors.patch
	cd embench-iot && patch -p1 < ../0001-return-success-value.patch

.PHONY: build
build: embench-iot
	cp rv_0x10000.ld embench-iot/config/riscv32/chips/tapasco-riscv/
	cd embench-iot && python3 build_all.py -v --clean --arch riscv32 --board tapasco-riscv --chip tapasco-riscv-libtool --builddir 32bit

.PHONY: collect
collect: build
	$(eval TARGET32 := $(filter-out %.o, $(notdir $(wildcard embench-iot/32bit/src/*/*))))

collect_binaries: build
	@$(MAKE) $(foreach target, $(TARGET32:%.in=%), out/$(target)/32bit/bsv_hex/$(target).bsv.txt)

.PHONY: collect_binaries out/%.bsv.txt
out/%.bsv.txt:
	@echo collecting $(notdir $(basename $@))
	@mkdir -p $(dir $@)
	@mkdir -p $(dir $@)/../elf
	@mkdir -p $(dir $@)/../bin
	@mkdir -p $(dir $@)/../ver
	@mkdir -p $(dir $@)/../dump
	
	@$(eval TNAME := $(word 2, $(subst /, ,$@)))
	@$(eval ARCH := $(word 3, $(subst /, ,$@)))
	
	@cp embench-iot/${ARCH}/src/${TNAME}/${TNAME} out/${TNAME}/${ARCH}/elf/${TNAME}.elf
	@${CROSS_COMPILE}-objcopy -O verilog embench-iot/${ARCH}/src/${TNAME}/${TNAME} out/${TNAME}/${ARCH}/ver/${TNAME}.verilog.txt
	@${CROSS_COMPILE}-objcopy -O binary embench-iot/${ARCH}/src/${TNAME}/${TNAME} out/${TNAME}/${ARCH}/bin/${TNAME}.bin
	@${CROSS_COMPILE}-objdump -d embench-iot/${ARCH}/src/${TNAME}/${TNAME} >out/${TNAME}/${ARCH}/dump/${TNAME}.dump
	@python3 ../hexConverter/hexConverter.py out/${TNAME}/${ARCH}/bin/${TNAME}.bin -o out/${TNAME}/${ARCH}/bsv_hex/${TNAME} -b 0x10000

.PHONY: install
install: collect collect_binaries
	@echo installing
	@mkdir -p ../../testPrograms/embench/
	@cp -r out/* ../../testPrograms/embench/

.PHONY: clean
clean:
	rm -rf out

