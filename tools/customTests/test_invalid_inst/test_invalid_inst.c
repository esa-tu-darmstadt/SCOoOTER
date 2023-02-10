#include "../rv_pe.h"
#include "../csr.h"
#include "../print.h"

int cnt = 0;

__attribute__((interrupt))
void trap_handler() {
	cnt = cnt+1;
	// modify return addr
	char buf[50];
	//sprintf (buf, "%x\n", csr_read_mcause());
	printnum(csr_read_mcause(), 16, buf);
	print(buf);
	print("\n");
	uint_xlen_t ptr = csr_read_mepc();
	csr_write_mepc(ptr+4);
}

int main() {
	print("hi mom!\n");
	csr_write_mtvec(trap_handler);
	asm("UNIMP"); // illegal instruction
	writeToCtrl(RETL, cnt);
	setIntr();
	return 0;
}

