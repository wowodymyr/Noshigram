#include "noshi_tab_order.h"
#include "test_util.h"

int main(void) {
    int order[] = {NOSHI_TAB_CHATS, NOSHI_TAB_CONTACTS, NOSHI_TAB_SETTINGS, NOSHI_TAB_PROFILE};
    int invalid[] = {NOSHI_TAB_CHATS, NOSHI_TAB_CHATS, NOSHI_TAB_SETTINGS, NOSHI_TAB_PROFILE};
    CHECK(noshi_tab_order_valid(order, NOSHI_TAB_SLOTS));
    CHECK(!noshi_tab_order_valid(invalid, NOSHI_TAB_SLOTS));
    CHECK(!noshi_tab_order_valid(order, 3));
    CHECK(!noshi_tab_order_valid(NULL, NOSHI_TAB_SLOTS));
    CHECK(!noshi_tab_order_replace(order, 0, NOSHI_TAB_CALLS));
    CHECK_EQ_INT(order[0], NOSHI_TAB_CHATS);
    CHECK(noshi_tab_order_replace(order, 1, NOSHI_TAB_CALLS));
    CHECK_EQ_INT(order[1], NOSHI_TAB_CALLS);
    CHECK(noshi_tab_order_replace(order, 0, NOSHI_TAB_SETTINGS));
    CHECK_EQ_INT(order[0], NOSHI_TAB_SETTINGS);
    CHECK_EQ_INT(order[2], NOSHI_TAB_CHATS);
    CHECK(noshi_tab_order_move(order, 0, 3));
    CHECK_EQ_INT(order[3], NOSHI_TAB_SETTINGS);
    CHECK(noshi_tab_order_move(order, 3, 0));
    CHECK_EQ_INT(order[0], NOSHI_TAB_SETTINGS);
    CHECK(!noshi_tab_order_move(order, 4, 0));
    CHECK(!noshi_tab_order_replace(order, 0, NOSHI_TAB_KINDS));
    CHECK(noshi_tab_order_valid(order, NOSHI_TAB_SLOTS));
    for (size_t from = 0; from < NOSHI_TAB_SLOTS; ++from) {
        for (size_t to = 0; to < NOSHI_TAB_SLOTS; ++to) {
            int copy[] = {NOSHI_TAB_CHATS, NOSHI_TAB_CONTACTS, NOSHI_TAB_SETTINGS, NOSHI_TAB_PROFILE};
            CHECK(noshi_tab_order_move(copy, from, to));
            CHECK(noshi_tab_order_valid(copy, NOSHI_TAB_SLOTS));
            CHECK(noshi_tab_order_move(copy, to, from));
            for (size_t i = 0; i < NOSHI_TAB_SLOTS; ++i) CHECK_EQ_INT(copy[i], (int)i);
        }
    }
    return test_finish("test_tab_order");
}
