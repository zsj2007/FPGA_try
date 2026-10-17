#include "ccl_ps.h"
#include <string.h>
#include <limits.h>

static unsigned root(ccl_context *c, unsigned x) {
    while (c->parent[x] != x) {
        c->parent[x] = c->parent[c->parent[x]];
        x = c->parent[x];
    }
    return x;
}
static void unite(ccl_context *c, unsigned a, unsigned b) {
    a = root(c, a); b = root(c, b);
    if (a == b) return;
    if (c->rank[a] < c->rank[b]) { unsigned t = a; a = b; b = t; }
    c->parent[b] = (uint16_t)a;
    if (c->rank[a] == c->rank[b]) ++c->rank[a];
}
static void add(ccl_blob *dst, const ccl_blob *src) {
    if (!dst->area) { *dst = *src; return; }
    dst->area += src->area;
    dst->sum_x += src->sum_x; dst->sum_y += src->sum_y;
    if (src->min_x < dst->min_x) dst->min_x = src->min_x;
    if (src->max_x > dst->max_x) dst->max_x = src->max_x;
    if (src->min_y < dst->min_y) dst->min_y = src->min_y;
    if (src->max_y > dst->max_y) dst->max_y = src->max_y;
}
int ccl_ps_feed(ccl_context *c, const uint32_t w[8]) {
    unsigned kind = w[0] & 255, a = (w[0] >> 8) & 255, b = (w[0] >> 16) & 255;
    if (kind == 0) {
        memset(c, 0, sizeof(*c));
        for (unsigned i = 0; i < CCL_LABELS; ++i) c->parent[i] = (uint16_t)i;
        c->active = true;
        return 0;
    }
    if (!c->active || c->failed) return -1;
    if (kind == 1 && a && b && !c->dumping) {
        unite(c, a, b);
        if (a > c->max_edge) c->max_edge = a;
        if (b > c->max_edge) c->max_edge = b;
        return 0;
    }
    if (kind == 2 && a && !c->seen[a] && a == c->count + 1 && w[1]) {
        ccl_blob s = {w[1], w[2], w[3], (uint16_t)w[4], (uint16_t)(w[4] >> 16),
                      (uint16_t)w[5], (uint16_t)(w[5] >> 16)};
        if (s.min_x > s.max_x || s.min_y > s.max_y) goto invalid;
        c->dumping = true;
        c->seen[a] = true;
        ++c->count;
        // All UNION events precede STAT: roots cannot change during aggregation.
        add(&c->blobs[root(c, a)], &s);
        return 0;
    }
    if (kind == 3 && !w[1] && a == c->count && c->max_edge <= a) {
        c->active = false;
        return 1;
    }
invalid:
    c->failed = true;
    return -1;
}
ccl_target ccl_ps_select(const ccl_context *c, uint32_t min_area) {
    ccl_target best = {0};
    uint32_t error = UINT32_MAX;
    if (c->active || c->failed) return best;
    for (unsigned i = 1; i < CCL_LABELS; ++i) {
        const ccl_blob *s = &c->blobs[i];
        if (!s->area || s->area < min_area) continue;
        uint32_t width = (uint32_t)s->max_x - s->min_x + 1;
        uint32_t height = (uint32_t)s->max_y - s->min_y + 1;
        uint32_t delta = width > height ? width-height : height-width;
        if (delta < error || (delta == error && s->area > best.blob.area)) {
            error = delta; best.valid = true; best.blob = *s;
            best.center_x = (uint16_t)(s->sum_x / s->area);
            best.center_y = (uint16_t)(s->sum_y / s->area);
        }
    }
    return best;
}
