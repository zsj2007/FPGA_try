#ifndef CCL_PS_H
#define CCL_PS_H
#include <stdint.h>
#include <stdbool.h>
#define CCL_LABELS 256
typedef struct {
    uint64_t area, sum_x, sum_y;
    uint16_t min_x, max_x, min_y, max_y;
} ccl_blob;
typedef struct {
    uint16_t parent[CCL_LABELS];
    uint8_t rank[CCL_LABELS];
    bool seen[CCL_LABELS], active, dumping, failed;
    unsigned count, max_edge;
    ccl_blob blobs[CCL_LABELS];
} ccl_context;
typedef struct {
    bool valid;
    uint16_t center_x, center_y;
    ccl_blob blob;
} ccl_target;
// Initialize to {0}. Feed complete eight-word events in order.
// Returns 0: pending, 1: completed frame, -1: invalid/overflow frame.
// START resets state; inspect/select blobs only after a return value of 1.
int ccl_ps_feed(ccl_context *ctx, const uint32_t words[8]);
ccl_target ccl_ps_select(const ccl_context *ctx, uint32_t min_area);
#endif
