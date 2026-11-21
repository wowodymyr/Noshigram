#ifndef NOSHI_LIST_STATE_H
#define NOSHI_LIST_STATE_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    NOSHI_LIST_CONTENT,
    NOSHI_LIST_LOADING,
    NOSHI_LIST_EMPTY,
    NOSHI_LIST_FAILED
} noshi_list_state;

typedef struct noshi_list_presentation {
    noshi_list_state state;
    int table_visible;
} noshi_list_presentation;

/* the selected list can be empty even when another folder loaded before it; its header must remain reachable */
noshi_list_presentation noshi_list_present(size_t item_count, int loading, int failed, int has_header);
int noshi_list_flood_wait(const char *error, uint32_t *seconds);
uint64_t noshi_list_flood_deadline(uint64_t current, uint64_t now, uint32_t seconds);
uint32_t noshi_list_flood_remaining(uint64_t deadline, uint64_t now);
/* coalesce updates and leave at least interval_ms between list requests */
uint64_t noshi_list_refresh_delay(uint64_t now, uint64_t last, uint32_t interval_ms, uint32_t debounce_ms);

#endif
