#include "../rv_pe.h"
#include "../print.h"
#include "../csr.h"

int main() {

	int* print_addr = 0x11008008;

	*print_addr = csr_read_mhartid();

	
	return 0;
}

