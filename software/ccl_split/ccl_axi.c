#include "ccl_axi.h"
bool ccl_axi_read_event(volatile uint32_t *base, uint32_t words[8]) {
    if (!(base[0] & 1u)) return false;
    for (unsigned i=0;i<8;++i) words[i] = base[0x20/4+i];
    base[0x08/4] = 1; // POP only after all words have been read
    return true;
}
void ccl_axi_write_target(volatile uint32_t *base, const ccl_target *t, uint32_t frame_id) {
    base[0x40/4] = ((uint32_t)t->center_y<<16) | t->center_x;
    base[0x44/4] = ((uint32_t)t->blob.max_x<<16) | t->blob.min_x;
    base[0x48/4] = ((uint32_t)t->blob.max_y<<16) | t->blob.min_y;
    base[0x4c/4] = (uint32_t)t->blob.area;
    base[0x50/4] = t->valid ? 1u : 0u;
    base[0x54/4] = frame_id;
    base[0x58/4] = 1; // atomic commit to output registers
}
