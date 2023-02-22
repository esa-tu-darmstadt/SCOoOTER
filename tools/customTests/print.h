#define OFFSET 0x11008000

char* out = (char*)OFFSET;

void print(char* str) {
	while(*out = *(str++));
}

void printnum(unsigned int num, int base, char *outbuf)
{
    for(int i = 8; i > 0; i--) {
        outbuf[i-1] = "0123456789ABCDEF"[num % base];
        num = num/base;
    }

    outbuf[8] = 0;
}
