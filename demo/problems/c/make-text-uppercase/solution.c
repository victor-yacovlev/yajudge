#include <stdio.h>

int main()
{
    int input_symbol = EOF;
    const char table_offset = 'a' - 'A';
    while (1) {
        input_symbol = getchar_unlocked();
        if (EOF == input_symbol) {
            break;
        }
        if ('a' <= input_symbol && input_symbol <= 'z') {
            putchar_unlocked(input_symbol - table_offset);
        } else {
            putchar_unlocked(input_symbol);
        }
    }
}
