/* 
 * Copyright (c) 2019-2020 Embedded Systems and Applications, TU Darmstadt.
 * This file is part of RT-LIFE
 * (see https://github.com/esa-tu-darmstadt/RT-LIFE).
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#define CTRL_OFFSET 0x11000000
#define IAR  0x1000
#define RETL 0x04
#define RETH 0x05
#define ARG0 0x08
#define ARG1 0x0C
#define ARG2 0x10
#define ARG3 0x14
#define ARG4 0x18
#define COUNTER 0x1c
#define COUNTERH 0x1d

/**
	Writes the value at the specified register.
	Example: writeToCtrl(RETL, 42); writes 42 to the lower 32 bits of return value register.
	@param reg The target register
	@param value The value to write to
**/
void writeToCtrl(int reg, int value)
{
	int* start = (int*)CTRL_OFFSET;
	int* addr = start + reg;
	*addr = value;
}


/**
	Returns the value of the specified reg from the RVController.
	Example: readFromCtrl(ARG0) -> returns value of ARG0 register
	@param reg The register to read from
	@return Value of reg.
**/
int readFromCtrl(int reg)
{
	int* start = (int*)CTRL_OFFSET;
	return *(start + reg);
}

/**
	Emits the interrupt from the RVController. Signals end of job. This function needs to be called *once* at the end of main.
**/
void setIntr()
{
	int* start = (int*)CTRL_OFFSET;
	int* addr = start + IAR;
	*addr = 1;
	while(1){}
}

