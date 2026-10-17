#ifndef CCL_AXI_H
#define CCL_AXI_H
#include "ccl_ps.h"
// Map as Device/uncached memory. One consumer only; no concurrent POP.
// MMIO ordering/barriers must follow the board BSP's ARM memory attributes.
bool ccl_axi_read_event(volatile uint32_t *base, uint32_t words[8]);
void ccl_axi_write_target(volatile uint32_t *base, const ccl_target *target, uint32_t frame_id);
#endif
