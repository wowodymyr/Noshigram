#ifndef NOSHI_TAB_ORDER_H
#define NOSHI_TAB_ORDER_H

#include <stddef.h>

enum { NOSHI_TAB_CHATS, NOSHI_TAB_CONTACTS, NOSHI_TAB_SETTINGS, NOSHI_TAB_PROFILE, NOSHI_TAB_CALLS, NOSHI_TAB_KINDS };
enum { NOSHI_TAB_SLOTS = 4 };

int noshi_tab_order_valid(const int *order, size_t count);
int noshi_tab_order_replace(int order[NOSHI_TAB_SLOTS], size_t slot, int kind);
int noshi_tab_order_move(int order[NOSHI_TAB_SLOTS], size_t from, size_t to);

#endif
