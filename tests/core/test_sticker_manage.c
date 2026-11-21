#include "test_util.h"
#include "noshi_sticker_manage.h"
#include "noshi_tl_ids.h"

static noshi_arena arena;

static void test_uninstall(void) {
    noshi_tl_value *request = NULL;
    const noshi_tl_value *set;
    noshi_writer wire;
    int64_t id = 0, hash = 0;
    CHECK_EQ_INT(noshi_sticker_uninstall_request(&arena, 77, 99, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_uninstallStickerSet);
    set = noshi_tl_get(request, "stickerset");
    CHECK(noshi_tl_is(set, NOSHI_TL_ID_inputStickerSetID));
    CHECK_EQ_INT(noshi_tl_get_i64(set, "id", &id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_get_i64(set, "access_hash", &hash), NOSHI_OK);
    CHECK_EQ_INT(id, 77);
    CHECK_EQ_INT(hash, 99);
    noshi_writer_init(&wire, 128);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_sticker_uninstall_request(&arena, 0, 99, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_sticker_uninstall_request(&arena, -5, 99, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sticker_uninstall_request(NULL, 5, 99, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sticker_uninstall_request(&arena, 5, 99, NULL), NOSHI_E_ARG);
}

static void test_install(void) {
    noshi_tl_value *request = NULL, *answer;
    const noshi_tl_value *set;
    noshi_writer wire;
    int64_t id = 0;
    CHECK_EQ_INT(noshi_sticker_install_request(&arena, 77, 99, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_installStickerSet);
    set = noshi_tl_get(request, "stickerset");
    CHECK(noshi_tl_is(set, NOSHI_TL_ID_inputStickerSetID));
    CHECK_EQ_INT(noshi_tl_get_i64(set, "id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 77);
    CHECK(noshi_tl_is(noshi_tl_get(request, "archived"), NOSHI_TL_ID_boolFalse));
    noshi_writer_init(&wire, 128);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_sticker_install_request(&arena, 0, 99, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_sticker_install_request(&arena, 5, 99, NULL), NOSHI_E_ARG);
    answer = noshi_tl_new_obj(&arena, "messages.stickerSetInstallResultSuccess");
    CHECK_EQ_INT(noshi_sticker_install_parse(answer), NOSHI_OK);
    CHECK_EQ_INT(noshi_sticker_install_parse(noshi_tl_new_obj(&arena, "boolTrue")), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_sticker_install_parse(NULL), NOSHI_E_MALFORMED);
}

static void test_reorder(void) {
    noshi_tl_value *request = NULL;
    const noshi_tl_value *order = NULL;
    noshi_writer wire;
    const int64_t ids[] = {30, 10, 20};
    const int64_t twice[] = {30, 10, 30};
    const int64_t bad[] = {30, 0};
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, ids, 3, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_messages_reorderStickerSets);
    CHECK_EQ_INT(noshi_tl_get_vec(request, "order", &order), NOSHI_OK);
    CHECK_EQ_INT(order->u.vec.count, 3);
    CHECK_EQ_INT(order->u.vec.items[0]->u.i64, 30);
    CHECK_EQ_INT(order->u.vec.items[2]->u.i64, 20);
    CHECK(!noshi_tl_has(request, "masks"));
    noshi_writer_init(&wire, 128);
    CHECK_EQ_INT(noshi_tl_encode(request, &wire, NULL), NOSHI_OK);
    noshi_writer_free(&wire);
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, twice, 3, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, bad, 2, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, ids, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, ids, NOSHI_STICKER_ORDER_MAX + 1, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, NULL, 3, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_sticker_reorder_request(&arena, ids, 3, NULL), NOSHI_E_ARG);
}

static void test_parse(void) {
    noshi_tl_value *yes = noshi_tl_new_obj(&arena, "boolTrue"), *no = noshi_tl_new_obj(&arena, "boolFalse"), *other = noshi_tl_new_obj(&arena, "updates");
    CHECK_EQ_INT(noshi_sticker_manage_parse(yes), NOSHI_OK);
    CHECK_EQ_INT(noshi_sticker_manage_parse(no), NOSHI_E_STATE);
    CHECK_EQ_INT(noshi_sticker_manage_parse(other), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_sticker_manage_parse(NULL), NOSHI_E_MALFORMED);
}

int main(void) {
    noshi_arena_init(&arena, 1024u * 1024u);
    test_uninstall();
    test_install();
    test_reorder();
    test_parse();
    noshi_arena_free(&arena);
    return test_finish("test_sticker_manage");
}
