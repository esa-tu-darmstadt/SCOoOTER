#include "../rv_pe.h"
#include "../csr.h"
#include "../print.h"

int cnt = 0;

__attribute__((interrupt))
void trap_handler() {
	print("hi mom!\n");
	uint_xlen_t cause = csr_read_mcause()&~0x80000000;
	char buf[9];
	printnum(cause, 10, buf);
	print(buf);
	print("\n");
}

int main() {
	print("GuMo!\n");
	csr_write_mtvec(trap_handler);
	csr_write_mie(0xffffffff);
	int test = 0;
	char buf[9];
	while(1) {
		printnum(test++, 10, buf);
		print(buf);
		print("\n");
	}
	writeToCtrl(RETL, cnt);
	setIntr();
	return 0;
}

