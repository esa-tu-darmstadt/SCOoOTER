#include "../rv_pe.h"
#include "../print.h"



#define ITERATIONS 4

static volatile int cnt = 0;
static volatile int hartid_max = 0;
static volatile int arrived = 0;
static volatile int mutex = 0;

int main() {
	
	// read HARTID
	register int hartid;        
	__asm__ volatile ("csrr    %0, mhartid" 
		              : "=r" (hartid)  /* output : register */
		              : /* input : none */
		              : /* clobbers: none */);
	
	// store maximum hartid of this system
	__asm__ volatile ("amomax.w.aq    x0, %0, (%1)"  
		                          : /* output: register %0 */
		                          : "r" (hartid)  /* input : register */
		                          , "r" ( &hartid_max ));
		                          
	// add multiple times with our mutex
	for(register int i = 0; i < ITERATIONS; i++) {
	
		// claim mutex
		register int out = 1;
		do {
			__asm__ volatile ("amoswap.w.aq    %0, %1, (%2)"  
				                  : "=r" (out) /* output: register %0 */
				                  : "r" (out)  /* input : register */
				                  , "r" ( &mutex ));
		} while (out != 0);
		
		// increase count
		cnt++;
			
		// release mutex		
		 __asm__ volatile ("amoswap.w.rl    zero, zero, (%0)"  /* output: register %0 */
		                          : : "r" ( &mutex ));
	}
	
	// signal that this hart is finished
	register int in = 1;
	__asm__ volatile ("amoadd.w.aq    x0, %0, (%1)"  
		                          : // output: register %0 
		                          : "r" (in)  // input : register 
		                          , "r" ( &arrived ));
		
	// wait for all harts to finish                     
	while(arrived != hartid_max+1);
	
	
	// write return value
	if(hartid == 0) {
		writeToCtrl(RETL, cnt==(hartid_max+1)*ITERATIONS);
		setIntr();
	}
	
	
	return 0;
}

