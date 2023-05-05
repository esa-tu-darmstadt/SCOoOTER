#include "../rv_pe.h"
#include "../print.h"
#include "../csr.h"

volatile uint_xlen_t cnt = 0;


static inline int update_cnt() {
    register uint_xlen_t out;
    register uint_xlen_t info;
    // amoswap.w	a4,a1,(a3)
   	    __asm__ volatile ("lr.w.aq    %0, (%1)"  
		                          : "=r" (out) /* output: register %0 */
		                          : "r" ( &cnt ));
		                          
	    __asm__ volatile ("sc.w.rl    %0, %1, (%2)"  
		                          : "=r" (info) /* output: register %0 */
		                          : "r" (out+1)  /* input : register */
		                          , "r" ( &cnt ));
	return info;
}

int main() {
	char buf[16];
	
	while(1) {
		register int res = update_cnt();
		if(!res) {
			print(".");
		}
		if(cnt == 50) break;
	}
	setIntr();
	return 0;
}

