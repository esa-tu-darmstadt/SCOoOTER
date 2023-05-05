#include "../rv_pe.h"
#include "../print.h"
#include "../csr.h"

volatile uint_xlen_t mutex = 0;
uint_xlen_t cnt = 0;

volatile int arr[] = {65, 47, 362, 455, 868, 22, 5, 6, 33, 1, 9, 5, 77, 14, 4, 978};
volatile int amount = 16;

int main() {
	volatile int cnt = 0;
	volatile int hartid_max = 0;
	volatile int arrived = 0;
	
	__asm__ volatile ("amomax.w.aq    x0, %0, (%1)"  
		                          : /* output: register %0 */
		                          : "r" (csr_read_mhartid())  /* input : register */
		                          , "r" ( &hartid_max ));
	
	register int i = 0;
	while((i*(hartid_max+1)+csr_read_mhartid()) < amount) {
		__asm__ volatile ("amoxor.w    x0, %0, (%1)"  
		                          : /* output: register %0 */
		                          : "r" (arr[(i*(hartid_max+1)+csr_read_mhartid())])  /* input : register */
		                          , "r" ( &cnt ));
		i++;
	}
	
	__asm__ volatile ("amoadd.w.aq    x0, %0, (%1)"  
		                          : // output: register %0 
		                          : "r" (1)  // input : register 
		                          , "r" ( &arrived ));
		                     
	while(arrived != hartid_max+1);
	
	if(csr_read_mhartid() == 0) {
		register int control = 0;
		for(register int i = 0; i < amount; i++) control ^= arr[i];
		writeToCtrl(RETL, cnt==control);
		setIntr();
	}
	
	
	return 0;
}

