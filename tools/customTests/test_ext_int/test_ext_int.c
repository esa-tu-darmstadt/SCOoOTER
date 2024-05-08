#include "../rv_pe.h"
#include "../csr.h"
#include "../print.h"

int cnt = 0;
volatile int cnt_ints = 0;

__attribute__((interrupt))
void trap_handler() {
	print("hi mom!\n");
	uint_xlen_t cause = csr_read_mcause()&~0x80000000;
	char buf[9];
	printnum(cause, 10, buf);
	print(buf);
	print("\n");
	if (cnt_ints > 20) setIntr();
	cnt_ints++;
}

int main() {
	print("GuMo!\n");
	csr_write_mtvec(trap_handler);
	csr_write_mie(1<<11);
	int test = 0;
	char buf[9];
	while(1) {
		printnum(test++, 10, buf);
		csr_write_mie(0);
		print(buf);
		print("\n");
		csr_write_mie(1<<7);
	}
	return 0;
}

