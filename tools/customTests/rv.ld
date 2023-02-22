ENTRY(_start)

SECTIONS
{
	. = 0x00000000;
	.text.init : {
			* (.text.init);
	}
	.text : {
	      * (.text);
	}
	. = 0x10000;
	.data : {
	      * (.data);
	}
	.srodata : {
	      * (.srodata);
	}
	.rodata : {
	      * (.rodata);
	}
	.bss : {
	     * (.bss);
	}
}
