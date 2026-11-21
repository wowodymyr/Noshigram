#include "noshi_gifts.h"

#include <string.h>
#include "noshi_app_config.h"
#include "noshi_store.h"
#include "noshi_tl_ids.h"

noshi_status noshi_gift_convert_period_parse(const noshi_tl_value *answer, int32_t *seconds) {
    return noshi_app_config_i32(answer, "stargifts_convert_period_max", seconds);
}

int noshi_gift_can_convert(const noshi_saved_gift *gift, int64_t now, int32_t period) {
    return gift && !gift->gift.unique && !gift->gift.auction && !gift->refunded && gift->convert_stars > 0 &&
           gift->date > 0 && period > 0 && now >= gift->date && now - gift->date < period;
}

static noshi_status stars_of(const noshi_tl_value *amount, int64_t *stars) {
    if (noshi_tl_is(amount, NOSHI_TL_ID_starsTonAmount)) return NOSHI_E_UNSUPPORTED;
    if (!noshi_tl_is(amount, NOSHI_TL_ID_starsAmount) || noshi_tl_get_i64(amount, "amount", stars) != NOSHI_OK ||
        *stars < 0) return NOSHI_E_MALFORMED;
    return NOSHI_OK;
}

noshi_status noshi_gifts_parse(const noshi_tl_value *answer, noshi_gift *gifts, size_t cap, size_t *count, int32_t *hash) {
    const noshi_tl_value *list;
    uint32_t i;
    size_t n = 0, pass;
    if (count) *count = 0;
    if (hash) *hash = 0;
    if (!gifts || !count || !cap) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_payments_starGiftsNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_payments_starGifts) || noshi_tl_get_vec(answer, "gifts", &list) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    if (list->u.vec.count > NOSHI_GIFTS_MAX * 2) return NOSHI_E_LIMIT;
    if (hash) noshi_tl_get_i32(answer, "hash", hash);
    /* the gifts that can still be bought come first, then the sold out ones, each group in server order */
    for (pass = 0; pass < 2; ++pass) {
        for (i = 0; i < list->u.vec.count && n < cap; ++i) {
            noshi_gift gift;
            if (noshi_gift_read(list->u.vec.items[i], &gift) != NOSHI_OK || gift.unique) continue;
            if ((gift.sold_out || gift.auction) != (pass == 1)) continue;
            gifts[n++] = gift;
        }
    }
    *count = n;
    return NOSHI_OK;
}

static const noshi_tl_value *find_user(const noshi_tl_value *users, int64_t id) {
    uint32_t i;
    for (i = 0; users && i < users->u.vec.count; ++i) {
        int64_t user_id;
        if (noshi_tl_get_i64(users->u.vec.items[i], "id", &user_id) == NOSHI_OK && user_id == id) return users->u.vec.items[i];
    }
    return NULL;
}

static void copy_note(char *dst, size_t cap, const noshi_tl_value *text) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (!text || noshi_tl_get_bytes(text, "text", &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static noshi_status read_saved(const noshi_tl_value *item, const noshi_tl_value *users, noshi_saved_gift *out) {
    noshi_peer from;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(item, NOSHI_TL_ID_savedStarGift) || noshi_tl_get_i32(item, "date", &out->date) != NOSHI_OK ||
        noshi_gift_read(noshi_tl_get(item, "gift"), &out->gift) != NOSHI_OK) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    out->name_hidden = noshi_tl_has(item, "name_hidden") ? 1 : 0;
    out->unsaved = noshi_tl_has(item, "unsaved") ? 1 : 0;
    out->can_upgrade = noshi_tl_has(item, "can_upgrade") ? 1 : 0;
    out->pinned = noshi_tl_has(item, "pinned_to_top") ? 1 : 0;
    out->refunded = noshi_tl_has(item, "refunded") ? 1 : 0;
    noshi_tl_get_i32(item, "msg_id", &out->msg_id);
    noshi_tl_get_i64(item, "convert_stars", &out->convert_stars);
    noshi_tl_get_i64(item, "upgrade_stars", &out->upgrade_stars);
    noshi_tl_get_i64(item, "transfer_stars", &out->transfer_stars);
    noshi_tl_get_i32(item, "can_transfer_at", &out->can_transfer_at);
    copy_note(out->note, sizeof(out->note), noshi_tl_get(item, "message"));
    noshi_entities_read(noshi_tl_get(item, "message"), out->note_entities, NOSHI_MESSAGE_ENTITIES_MAX,
                          out->note_urls, sizeof(out->note_urls), &out->note_entity_count);
    if (!out->name_hidden && noshi_peer_from_tl(noshi_tl_get(item, "from_id"), &from) == NOSHI_OK && from.kind == 1) {
        noshi_person_row person;
        const noshi_tl_value *user = find_user(users, from.id);
        out->from_id = from.id;
        if (user && noshi_person_parse(user, &person) == NOSHI_OK) {
            strncpy(out->from_name, person.name, sizeof(out->from_name) - 1);
            out->from_name[sizeof(out->from_name) - 1] = 0;
            out->from_person = person;
        }
    }
    return NOSHI_OK;
}

noshi_status noshi_saved_gifts_parse(const noshi_tl_value *answer, noshi_saved_gift *rows, size_t cap, size_t *count,
                                         noshi_saved_gift_page *page) {
    const noshi_tl_value *list, *users;
    const uint8_t *offset;
    size_t offset_len, n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (page) memset(page, 0, sizeof(*page));
    if (!rows || !count || !page || !cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_payments_savedStarGifts) || noshi_tl_get_vec(answer, "gifts", &list) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (list->u.vec.count > NOSHI_SAVED_GIFTS_MAX) return NOSHI_E_LIMIT;
    noshi_tl_get_i32(answer, "count", &page->total);
    if (noshi_tl_has(answer, "next_offset") && noshi_tl_get_bytes(answer, "next_offset", &offset, &offset_len) == NOSHI_OK) {
        /* an offset that does not fit would restart the list at the wrong place, so the list ends here instead */
        if (offset_len > 0 && offset_len < sizeof(page->next_offset)) {
            memcpy(page->next_offset, offset, offset_len);
            page->next_offset[offset_len] = 0;
        }
    }
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        if (read_saved(list->u.vec.items[i], users, &rows[n]) == NOSHI_OK) ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_stars_balance_parse(const noshi_tl_value *answer, int64_t *stars) {
    if (stars) *stars = 0;
    if (!stars) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_payments_starsStatus)) return NOSHI_E_MALFORMED;
    return stars_of(noshi_tl_get(answer, "balance"), stars);
}

noshi_status noshi_payment_form_parse(const noshi_tl_value *answer, int64_t *form_id, int64_t *stars) {
    const noshi_tl_value *invoice, *prices;
    uint32_t i;
    int64_t total = 0;
    if (form_id) *form_id = 0;
    if (stars) *stars = 0;
    if (!form_id || !stars) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentFormStarGift)) {
        return noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentForm) || noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentFormStars)
            ? NOSHI_E_UNSUPPORTED : NOSHI_E_MALFORMED;
    }
    invoice = noshi_tl_get(answer, "invoice");
    if (noshi_tl_get_i64(answer, "form_id", form_id) != NOSHI_OK || !noshi_tl_is(invoice, NOSHI_TL_ID_invoice) ||
        noshi_tl_get_vec(invoice, "prices", &prices) != NOSHI_OK || prices->u.vec.count == 0 || prices->u.vec.count > 16)
        return NOSHI_E_MALFORMED;
    for (i = 0; i < prices->u.vec.count; ++i) {
        int64_t amount;
        if (noshi_tl_get_i64(prices->u.vec.items[i], "amount", &amount) != NOSHI_OK || amount < 0 || amount > INT64_MAX - total) {
            *form_id = 0;
            return NOSHI_E_MALFORMED;
        }
        total += amount;
    }
    *stars = total;
    return NOSHI_OK;
}

noshi_status noshi_payment_result_check(const noshi_tl_value *answer) {
    if (noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentResult)) return NOSHI_OK;
    if (noshi_tl_is(answer, NOSHI_TL_ID_payments_paymentVerificationNeeded)) return NOSHI_E_UNSUPPORTED;
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_gifts_request(noshi_arena *arena, int32_t hash, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "payments.getStarGifts");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, request, "hash", hash);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_saved_gifts_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *offset, int32_t limit,
                                           noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !offset || strlen(offset) >= NOSHI_GIFT_OFFSET_MAX || limit < 1 || limit > NOSHI_SAVED_GIFTS_MAX) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "payments.getSavedStarGifts");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "offset", offset);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_saved_gifts_in_collection_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t collection_id, const char *offset,
                                                         int32_t limit, noshi_tl_value **out) {
    noshi_status status;
    if (out) *out = NULL;
    if (!out || collection_id <= 0) return NOSHI_E_ARG;
    status = noshi_saved_gifts_request(arena, peer, offset, limit, out);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *out, "collection_id", collection_id);
    if (status != NOSHI_OK) *out = NULL;
    return status;
}

noshi_status noshi_gift_collection_read(const noshi_tl_value *value, noshi_gift_collection *out) {
    const uint8_t *title;
    size_t length;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!noshi_tl_is(value, NOSHI_TL_ID_starGiftCollection) || noshi_tl_get_i32(value, "collection_id", &out->id) != NOSHI_OK || out->id <= 0 ||
        noshi_tl_get_bytes(value, "title", &title, &length) != NOSHI_OK || !length) return NOSHI_E_MALFORMED;
    noshi_tl_get_i32(value, "gifts_count", &out->count);
    if (out->count < 0) out->count = 0;
    /* a title the buffer cannot hold is cut at a character boundary */
    if (length >= sizeof(out->title)) {
        length = sizeof(out->title) - 1;
        while (length > 0 && (title[length] & 0xC0) == 0x80) --length;
    }
    memcpy(out->title, title, length);
    out->title[length] = 0;
    return length ? NOSHI_OK : NOSHI_E_MALFORMED;
}

noshi_status noshi_gift_collections_parse(const noshi_tl_value *answer, noshi_gift_collection *rows, size_t cap, size_t *count) {
    const noshi_tl_value *list;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!rows || !count || !cap) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_payments_starGiftCollectionsNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_payments_starGiftCollections) || noshi_tl_get_vec(answer, "collections", &list) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    if (list->u.vec.count > NOSHI_GIFT_COLLECTIONS_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        if (noshi_gift_collection_read(list->u.vec.items[i], &rows[n]) == NOSHI_OK) ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_gift_collections_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "payments.getStarGiftCollections");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* InputSavedStarGift of a gift on our own profile, which the server names by the id of its message */
static noshi_status saved_input(noshi_arena *arena, int32_t msg_id, noshi_tl_value **out);

static noshi_status saved_vector(noshi_arena *arena, const int32_t *ids, size_t count, noshi_tl_value **out) {
    noshi_tl_value *vec;
    size_t i;
    *out = NULL;
    if (!ids || count > NOSHI_GIFT_COLLECTION_BATCH_MAX) return NOSHI_E_ARG;
    vec = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!vec) return NOSHI_E_NOMEM;
    for (i = 0; i < count; ++i) {
        noshi_tl_value *input;
        noshi_status status = saved_input(arena, ids[i], &input);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(vec, (uint32_t)i, input);
        if (status != NOSHI_OK) return status;
    }
    *out = vec;
    return NOSHI_OK;
}

static int title_ok(const char *title) {
    size_t length = title ? strlen(title) : 0;
    return length > 0 && length < NOSHI_GIFT_COLLECTION_TITLE_MAX;
}

noshi_status noshi_gift_collection_create_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *title, const int32_t *msg_ids,
                                                      size_t count, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *gifts;
    noshi_status status;
    int32_t none = 0;
    if (out) *out = NULL;
    if (!arena || !out || !title_ok(title)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    status = saved_vector(arena, count ? msg_ids : &none, count, &gifts);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "payments.createStarGiftCollection");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "title", title);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stargift", gifts);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_collection_update_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t collection_id, const char *title,
                                                      const int32_t *add, size_t add_count, const int32_t *remove, size_t remove_count,
                                                      noshi_tl_value **out) {
    noshi_tl_value *request, *input, *vec;
    noshi_status status;
    int32_t none = 0;
    if (out) *out = NULL;
    if (!arena || !out || collection_id <= 0 || (title && !title_ok(title)) || (!title && !add_count && !remove_count)) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "payments.updateStarGiftCollection");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "collection_id", collection_id);
    if (status == NOSHI_OK && title) status = noshi_tl_set_str(arena, request, "title", title);
    if (status == NOSHI_OK && add_count) {
        status = saved_vector(arena, add ? add : &none, add_count, &vec);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "add_stargift", vec);
    }
    if (status == NOSHI_OK && remove_count) {
        status = saved_vector(arena, remove ? remove : &none, remove_count, &vec);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "delete_stargift", vec);
    }
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_collection_delete_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t collection_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || collection_id <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "payments.deleteStarGiftCollection");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "collection_id", collection_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_stars_balance_request(noshi_arena *arena, noshi_tl_value **out) {
    noshi_tl_value *request, *self;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "payments.getStarsStatus");
    self = noshi_tl_new_obj(arena, "inputPeerSelf");
    if (!request || !self) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", self);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* InputSavedStarGift of a gift on our own profile, which the server names by the id of its message */
static noshi_status saved_input(noshi_arena *arena, int32_t msg_id, noshi_tl_value **out) {
    noshi_tl_value *input;
    noshi_status status;
    *out = NULL;
    if (!arena || msg_id <= 0) return NOSHI_E_ARG;
    input = noshi_tl_new_obj(arena, "inputSavedStarGiftUser");
    if (!input) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i32(arena, input, "msg_id", msg_id);
    if (status == NOSHI_OK) *out = input;
    return status;
}

noshi_status noshi_gift_invoice_send(noshi_arena *arena, const noshi_peer_ref *peer, int64_t gift_id, const char *note,
                                         const noshi_send_entity *entities, size_t entity_count, int hide_name, int include_upgrade,
                                         noshi_tl_value **out) {
    noshi_tl_value *invoice, *input, *text, *list = NULL;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || gift_id <= 0 || !note || strlen(note) >= NOSHI_GIFT_NOTE_MAX) return NOSHI_E_ARG;
    status = noshi_send_entities_build(arena, note, entities, entity_count, &list);
    if (status != NOSHI_OK) return status;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    invoice = noshi_tl_new_obj(arena, "inputInvoiceStarGift");
    if (!invoice) return NOSHI_E_NOMEM;
    status = noshi_tl_set(invoice, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, invoice, "gift_id", gift_id);
    if (status == NOSHI_OK && hide_name) status = noshi_tl_set_flag(invoice, "hide_name");
    if (status == NOSHI_OK && include_upgrade) status = noshi_tl_set_flag(invoice, "include_upgrade");
    if (status == NOSHI_OK && note[0]) {
        text = noshi_tl_new_obj(arena, "textWithEntities");
        if (!text) return NOSHI_E_NOMEM;
        status = noshi_tl_set_str(arena, text, "text", note);
        if (status == NOSHI_OK) status = noshi_tl_set(text, "entities", list ? list : noshi_tl_new_vec(arena, 0));
        if (status == NOSHI_OK) status = noshi_tl_set(invoice, "message", text);
    }
    if (status == NOSHI_OK) *out = invoice;
    return status;
}

noshi_status noshi_gift_invoice_upgrade(noshi_arena *arena, int32_t msg_id, int keep_details, noshi_tl_value **out) {
    noshi_tl_value *invoice, *input;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = saved_input(arena, msg_id, &input);
    if (status != NOSHI_OK) return status;
    invoice = noshi_tl_new_obj(arena, "inputInvoiceStarGiftUpgrade");
    if (!invoice) return NOSHI_E_NOMEM;
    status = noshi_tl_set(invoice, "stargift", input);
    if (status == NOSHI_OK && keep_details) status = noshi_tl_set_flag(invoice, "keep_original_details");
    if (status == NOSHI_OK) *out = invoice;
    return status;
}

noshi_status noshi_gift_invoice_transfer(noshi_arena *arena, int32_t msg_id, const noshi_peer_ref *to, noshi_tl_value **out) {
    noshi_tl_value *invoice, *input, *target;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = saved_input(arena, msg_id, &input);
    if (status == NOSHI_OK) status = noshi_input_peer(arena, to, &target);
    if (status != NOSHI_OK) return status;
    invoice = noshi_tl_new_obj(arena, "inputInvoiceStarGiftTransfer");
    if (!invoice) return NOSHI_E_NOMEM;
    status = noshi_tl_set(invoice, "stargift", input);
    if (status == NOSHI_OK) status = noshi_tl_set(invoice, "to_id", target);
    if (status == NOSHI_OK) *out = invoice;
    return status;
}

noshi_status noshi_paid_media_invoice(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, noshi_tl_value **out) {
    noshi_tl_value *invoice, *target;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !peer || msg_id <= 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &target);
    if (status != NOSHI_OK) return status;
    invoice = noshi_tl_new_obj(arena, "inputInvoiceMessage");
    if (!invoice) return NOSHI_E_NOMEM;
    status = noshi_tl_set(invoice, "peer", target);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, invoice, "msg_id", msg_id);
    if (status == NOSHI_OK) *out = invoice;
    return status;
}

noshi_status noshi_payment_form_request(noshi_arena *arena, noshi_tl_value *invoice, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !invoice) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "payments.getPaymentForm");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "invoice", invoice);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_payment_send_request(noshi_arena *arena, int64_t form_id, noshi_tl_value *invoice, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || !invoice || form_id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "payments.sendStarsForm");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, request, "form_id", form_id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "invoice", invoice);
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* a request whose only argument is one of our received gifts */
static noshi_status saved_request(noshi_arena *arena, const char *name, int32_t msg_id, noshi_tl_value **request) {
    noshi_tl_value *input;
    noshi_status status = saved_input(arena, msg_id, &input);
    *request = NULL;
    if (status != NOSHI_OK) return status;
    *request = noshi_tl_new_obj(arena, name);
    if (!*request) return NOSHI_E_NOMEM;
    return noshi_tl_set(*request, "stargift", input);
}

noshi_status noshi_gift_save_request(noshi_arena *arena, int32_t msg_id, int unsave, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = saved_request(arena, "payments.saveStarGift", msg_id, &request);
    if (status == NOSHI_OK && unsave) status = noshi_tl_set_flag(request, "unsave");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_convert_request(noshi_arena *arena, int32_t msg_id, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = saved_request(arena, "payments.convertStarGift", msg_id, &request);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_upgrade_request(noshi_arena *arena, int32_t msg_id, int keep_details, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = saved_request(arena, "payments.upgradeStarGift", msg_id, &request);
    if (status == NOSHI_OK && keep_details) status = noshi_tl_set_flag(request, "keep_original_details");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_transfer_request(noshi_arena *arena, int32_t msg_id, const noshi_peer_ref *to, noshi_tl_value **out) {
    noshi_tl_value *request, *target;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    status = noshi_input_peer(arena, to, &target);
    if (status == NOSHI_OK) status = saved_request(arena, "payments.transferStarGift", msg_id, &request);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "to_id", target);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_pin_request(noshi_arena *arena, const int32_t *msg_ids, size_t count, noshi_tl_value **out) {
    noshi_tl_value *request, *self, *vec;
    noshi_status status = NOSHI_OK;
    size_t i;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    /* the profile shows at most six pinned gifts */
    if (!arena || (count && !msg_ids) || count > 6) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "payments.toggleStarGiftsPinnedToTop");
    self = noshi_tl_new_obj(arena, "inputPeerSelf");
    vec = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!request || !self || !vec) return NOSHI_E_NOMEM;
    for (i = 0; status == NOSHI_OK && i < count; ++i) {
        noshi_tl_value *input;
        status = saved_input(arena, msg_ids[i], &input);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(vec, (uint32_t)i, input);
    }
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", self);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "stargift", vec);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_gift_wear_request(noshi_arena *arena, int64_t collectible_id, noshi_tl_value **out) {
    noshi_tl_value *request, *status;
    noshi_status result;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || collectible_id < 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "account.updateEmojiStatus");
    status = noshi_tl_new_obj(arena, collectible_id ? "inputEmojiStatusCollectible" : "emojiStatusEmpty");
    if (!request || !status) return NOSHI_E_NOMEM;
    result = collectible_id ? noshi_tl_set_i64(arena, status, "collectible_id", collectible_id) : NOSHI_OK;
    if (result == NOSHI_OK) result = noshi_tl_set(request, "emoji_status", status);
    if (result == NOSHI_OK) *out = request;
    return result;
}
