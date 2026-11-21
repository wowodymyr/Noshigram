#include "noshi_jitter.h"

#include <string.h>

noshi_status noshi_jitter_init(noshi_jitter *j, unsigned target) {
    if (!j) return NOSHI_E_ARG;
    memset(j, 0, sizeof(*j));
    if (target < 1 || target > 16) return NOSHI_E_ARG;
    j->target = (uint8_t)target;
    return NOSHI_OK;
}

static void restart(noshi_jitter *j) {
    memset(j->slots, 0, sizeof(j->slots));
    j->count = 0;
    j->empty_reads = 0;
    j->playing = 0;
    j->has_expected = 0;
}

noshi_status noshi_jitter_put(noshi_jitter *j, uint16_t sequence, const uint8_t *data, size_t len) {
    noshi_jitter_slot *slot;
    int16_t ahead;
    if (!j || !data) return NOSHI_E_ARG;
    if (len == 0 || len > NOSHI_JITTER_MAX_PACKET) return NOSHI_E_LIMIT;
    if (!j->has_expected) {
        j->expected = sequence;
        j->has_expected = 1;
    }
    ahead = (int16_t)(uint16_t)(sequence - j->expected);
    if (ahead < 0) {
        ++j->late;
        return NOSHI_E_RETRY;
    }
    if (ahead >= NOSHI_JITTER_SLOTS) {
        /* the sender jumped, or the stream began again: nothing buffered fits any more */
        restart(j);
        ++j->resets;
        j->expected = sequence;
        j->has_expected = 1;
    }
    slot = &j->slots[sequence % NOSHI_JITTER_SLOTS];
    if (slot->used) {
        ++j->duplicates;
        return NOSHI_E_RETRY;
    }
    slot->used = 1;
    slot->sequence = sequence;
    slot->len = (uint16_t)len;
    memcpy(slot->data, data, len);
    ++j->count;
    if (!j->playing && j->count >= j->target) j->playing = 1;
    return NOSHI_OK;
}

noshi_jitter_kind noshi_jitter_get(noshi_jitter *j, uint8_t *out, size_t capacity, size_t *len) {
    noshi_jitter_slot *slot;
    if (len) *len = 0;
    if (!j || !out || !len || capacity < NOSHI_JITTER_MAX_PACKET || !j->playing) return NOSHI_JITTER_EMPTY;
    slot = &j->slots[j->expected % NOSHI_JITTER_SLOTS];
    if (slot->used && slot->sequence == j->expected) {
        memcpy(out, slot->data, slot->len);
        *len = slot->len;
        slot->used = 0;
        --j->count;
        ++j->expected;
        j->empty_reads = 0;
        return NOSHI_JITTER_FRAME;
    }
    if (j->count > 0) {
        ++j->lost;
        ++j->expected;
        j->empty_reads = 0;
        return NOSHI_JITTER_LOST;
    }
    if (++j->empty_reads >= NOSHI_JITTER_UNDERRUN_READS) restart(j);
    return NOSHI_JITTER_EMPTY;
}
