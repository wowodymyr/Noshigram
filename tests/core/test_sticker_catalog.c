#include "test_util.h"
#include "noshi_messages.h"
#include "noshi_tl_ids.h"

#include <string.h>

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static noshi_tl_value *header(int64_t id, const char *title, int flag_masks, int flag_emojis, int flag_installed, int flag_archived) {
    noshi_tl_value *set = obj("stickerSet");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, set, "id", id), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena, set, "access_hash", id * 7), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, set, "count", 12), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, set, "title", title), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena, set, "short_name", "pack"), NOSHI_OK);
    if (flag_masks) CHECK_EQ_INT(noshi_tl_set_flag(set, "masks"), NOSHI_OK);
    if (flag_emojis) CHECK_EQ_INT(noshi_tl_set_flag(set, "emojis"), NOSHI_OK);
    if (flag_installed) CHECK_EQ_INT(noshi_tl_set_i32(&arena, set, "installed_date", 100), NOSHI_OK);
    if (flag_archived) CHECK_EQ_INT(noshi_tl_set_flag(set, "archived"), NOSHI_OK);
    return set;
}

static noshi_tl_value *covered(const char *ctor, noshi_tl_value *set) {
    noshi_tl_value *c = obj(ctor);
    CHECK_EQ_INT(noshi_tl_set(c, "set", set), NOSHI_OK);
    return c;
}

static noshi_tl_value *vec_of(noshi_tl_value **items, uint32_t n) {
    noshi_tl_value *vec = noshi_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(noshi_tl_vec_set(vec, i, items[i]), NOSHI_OK);
    return vec;
}

static void test_featured(void) {
    static noshi_sticker_set_row rows[8];
    size_t count = 99;
    noshi_tl_value *request, *items[5], *answer;
    CHECK_EQ_INT(noshi_featured_stickers_request(&arena, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_is(request, NOSHI_TL_ID_messages_getFeaturedStickers), 1);

    /* every covered constructor carries the header; masks and emoji sets are left out, a set in the archive is not marked installed */
    items[0] = covered("stickerSetCovered", header(1, "cats", 0, 0, 0, 0));
    items[1] = covered("stickerSetMultiCovered", header(2, "dogs", 0, 0, 1, 0));
    items[2] = covered("stickerSetNoCovered", header(3, "masks", 1, 0, 0, 0));
    items[3] = covered("stickerSetCovered", header(4, "emoji", 0, 1, 0, 0));
    items[4] = covered("stickerSetFullCovered", header(5, "old", 0, 0, 1, 1));
    answer = obj("messages.featuredStickers");
    CHECK_EQ_INT(noshi_tl_set(answer, "sets", vec_of(items, 5)), NOSHI_OK);
    CHECK_EQ_INT(noshi_featured_stickers_parse(answer, rows, 8, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 3);
    CHECK_EQ_INT((int)rows[0].id, 1);
    CHECK_EQ_INT(rows[0].installed, 0);
    CHECK_EQ_INT((int)rows[1].id, 2);
    CHECK_EQ_INT(rows[1].installed, 1);
    CHECK_EQ_INT((int)rows[2].id, 5);
    CHECK_EQ_INT(rows[2].installed, 0);
    CHECK(strcmp(rows[0].title, "cats") == 0);

    CHECK_EQ_INT(noshi_featured_stickers_parse(answer, rows, 2, &count), NOSHI_OK);
    CHECK_EQ_INT((int)count, 2);
    CHECK_EQ_INT(noshi_featured_stickers_parse(obj("messages.featuredStickersNotModified"), rows, 8, &count), NOSHI_E_NOTFOUND);
    CHECK_EQ_INT(noshi_featured_stickers_parse(obj("messages.allStickers"), rows, 8, &count), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_featured_stickers_parse(NULL, rows, 8, &count), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_featured_stickers_parse(answer, rows, 0, &count), NOSHI_E_ARG);
}

static void test_archived(void) {
    static noshi_sticker_set_row rows[8];
    size_t count = 99;
    int32_t total = 99;
    noshi_tl_value *request, *items[2], *answer;
    CHECK_EQ_INT(noshi_archived_stickers_request(&arena, 0, 30, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_is(request, NOSHI_TL_ID_messages_getArchivedStickers), 1);
    CHECK_EQ_INT(noshi_tl_has(request, "masks"), 0);
    CHECK_EQ_INT(noshi_tl_has(request, "emojis"), 0);
    CHECK_EQ_INT(noshi_archived_stickers_request(&arena, 0, 0, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_archived_stickers_request(&arena, 0, 101, &request), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_archived_stickers_request(&arena, -1, 10, &request), NOSHI_E_ARG);

    items[0] = covered("stickerSetCovered", header(8, "a", 0, 0, 1, 1));
    items[1] = covered("stickerSetCovered", header(9, "mask", 1, 0, 1, 1));
    answer = obj("messages.archivedStickers");
    CHECK_EQ_INT(noshi_tl_set_i32(&arena, answer, "count", 40), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer, "sets", vec_of(items, 2)), NOSHI_OK);
    CHECK_EQ_INT(noshi_archived_stickers_parse(answer, rows, 8, &count, &total), NOSHI_OK);
    CHECK_EQ_INT((int)count, 1);
    CHECK_EQ_INT(total, 40);
    CHECK_EQ_INT(rows[0].installed, 0);
    CHECK_EQ_INT(noshi_archived_stickers_parse(obj("messages.featuredStickers"), rows, 8, &count, &total), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(total, 0);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_featured();
    test_archived();
    noshi_arena_free(&arena);
    return test_finish("test_sticker_catalog");
}
