#include <unistd.h>

// Readiness prevents scanning before exec; stdin EOF ends the fixture cleanly.
int main(void) {
    const char ready = 'R';
    if (write(STDOUT_FILENO, &ready, 1) != 1) {
        return 1;
    }
    char byte;
    while (read(STDIN_FILENO, &byte, 1) > 0) {}
    return 0;
}
