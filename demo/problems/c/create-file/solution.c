#include <stdio.h>

int main(int argrc, char* argv[])
{
    const char* file_name = argv[1];
    FILE* file = fopen(file_name, "a");
    fputs("Hello, World!", file);
}
