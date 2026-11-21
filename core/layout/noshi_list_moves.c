#include "noshi_list_moves.h"

#include <string.h>

noshi_status noshi_list_keep(const int32_t *target, size_t count, uint8_t *keep, size_t keep_cap) {
    /* tail[k] is the row that ends the best run of length k + 1, back[i] the row before i in its run */
    int32_t tail[NOSHI_LIST_MOVES_MAX], back[NOSHI_LIST_MOVES_MAX];
    uint8_t used[NOSHI_LIST_TARGET_MAX];
    size_t length = 0, i;
    if (count && (!target || !keep)) return NOSHI_E_ARG;
    if (count > NOSHI_LIST_MOVES_MAX) return NOSHI_E_LIMIT;
    if (keep_cap < count) return NOSHI_E_LIMIT;
    memset(used, 0, sizeof(used));
    for (i = 0; i < count; ++i) {
        keep[i] = 0;
        if (target[i] < -1) return NOSHI_E_ARG;
        if (target[i] >= NOSHI_LIST_TARGET_MAX) return NOSHI_E_LIMIT;
        if (target[i] < 0) continue;
        if (used[target[i]]) return NOSHI_E_ARG;
        used[target[i]] = 1;
    }
    for (i = 0; i < count; ++i) {
        size_t low = 0, high = length;
        if (target[i] < 0) continue;
        /* the first run end whose target is not below this one */
        while (low < high) {
            size_t middle = (low + high) / 2;
            if (target[tail[middle]] < target[i]) low = middle + 1;
            else high = middle;
        }
        back[i] = low ? tail[low - 1] : -1;
        tail[low] = (int32_t)i;
        if (low == length) ++length;
    }
    if (length) {
        int32_t at = tail[length - 1];
        while (at >= 0) {
            keep[at] = 1;
            at = back[at];
        }
    }
    return NOSHI_OK;
}
