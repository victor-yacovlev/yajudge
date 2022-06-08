#include <stdio.h>

int main()
{
    int value = 0;
    while (scanf("%d", &value) > 0) {
        value = value * value;
        printf("%d\n", value);
    }
}
