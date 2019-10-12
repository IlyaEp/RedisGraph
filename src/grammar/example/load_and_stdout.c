#include "../grammar.h"
#include <stdio.h>

int main() {
    // Small example of loading and out grammar.

    FILE *f = fopen("toy_cfg.txt", "r");
    Grammar gr;
    Grammar_Load(&gr, f);

    for (int i = 0; i < gr.simple_rules_count; i++) {
        printf("%d -> %d\n", gr.simple_rules[i].l, gr.simple_rules[i].r);
    }
    for (int i = 0; i < gr.complex_rules_count; ++i) {
        printf("%d -> %d %d\n", gr.complex_rules[i].l, gr.complex_rules[i].r1, gr.complex_rules[i].r2);
    }
    return 0;
}