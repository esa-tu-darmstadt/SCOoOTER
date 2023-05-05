
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

ARCH?="RV32"

ifeq ($(ARCH), "RV32")
	MARCH?="rv32ima"
	MABI?="ilp32"
	OUT?="32bit"
else
	MARCH?="rv64ima"
	MABI?="lp64"
	OUT?="64bit"
endif

CROSS_COMPILE?="riscv64-unknown-elf"
CFLAGS+=-march=${MARCH} -mabi=${MABI} -fno-zero-initialized-in-bss -O0 -nostdlib -T rv.ld startup.s -g
OFLAGS+=-O binary

TARGETS = $(subst /,, $(filter %/, $(wildcard test_*/)))
all: clean $(foreach target, $(TARGETS:%.in=%), out/$(target))

out/test_%:
	@echo building $@
	
	@# get directory and file names
	@$(eval d := $(lastword $(subst /, , $@)))
	
	@mkdir -p $d/../out
	
	@# make output dirs
	@mkdir -p $d/../out/$d/elf/
	@mkdir -p $d/../out/$d/bin/
	@mkdir -p $d/../out/$d/bsv/
	@mkdir -p $d/../out/$d/dump/
	
	@# compile
	@${CROSS_COMPILE}-gcc     $(CFLAGS)  -o $d/../out/$d/elf/$d.elf $d/$d.c
	@${CROSS_COMPILE}-objcopy $(OFLAGS)  $d/../out/$d/elf/$d.elf $d/../out/$d/bin/$d.bin
	@${CROSS_COMPILE}-objdump -d $d/../out/$d/elf/$d.elf > $d/../out/$d/dump/$d.dump
	@python3 ../hexConverter/hexConverter.py $d/../out/$d/bin/$d.bin -o $d/../out/$d/bsv/$d -b 0x10000

.PHONY: install

install:
	mkdir -p ../../testPrograms/custom
	cp -r out/* ../../testPrograms/custom


.PHONY: clean
clean:
	rm -rf out

