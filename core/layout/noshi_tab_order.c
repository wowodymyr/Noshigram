#include "noshi_tab_order.h"

int noshi_tab_order_valid(const int *order, size_t count) {
    unsigned seen = 0;
    size_t i;
    if (!order || count != NOSHI_TAB_SLOTS) return 0;
    for (i = 0; i < count; ++i) {
        unsigned bit;
        if (order[i] < 0 || order[i] >= NOSHI_TAB_KINDS) return 0;
        bit = 1u << (unsigned)order[i];
        if (seen & bit) return 0;
        seen |= bit;
    }
    return (seen & (1u << NOSHI_TAB_CHATS)) && (seen & (1u << NOSHI_TAB_SETTINGS));
}

int noshi_tab_order_replace(int order[NOSHI_TAB_SLOTS], size_t slot, int kind) {
    size_t i;
    int old;
    if (!noshi_tab_order_valid(order, NOSHI_TAB_SLOTS) || slot >= NOSHI_TAB_SLOTS || kind < 0 || kind >= NOSHI_TAB_KINDS) return 0;
    old = order[slot];
    for (i = 0; i < NOSHI_TAB_SLOTS; ++i) if (order[i] == kind) break;
    if (i == NOSHI_TAB_SLOTS && (old == NOSHI_TAB_CHATS || old == NOSHI_TAB_SETTINGS)) return 0;
    order[slot] = kind;
    if (i < NOSHI_TAB_SLOTS) order[i] = old;
    return 1;
}

int noshi_tab_order_move(int order[NOSHI_TAB_SLOTS], size_t from, size_t to) {
    int value;
    size_t i;
    if (!noshi_tab_order_valid(order, NOSHI_TAB_SLOTS) || from >= NOSHI_TAB_SLOTS || to >= NOSHI_TAB_SLOTS) return 0;
    value = order[from];
    if (from < to) for (i = from; i < to; ++i) order[i] = order[i + 1];
    else for (i = from; i > to; --i) order[i] = order[i - 1];
    order[to] = value;
    return 1;
}
