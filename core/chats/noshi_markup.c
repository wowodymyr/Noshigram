#include "noshi_markup.h"

#include <math.h>
#include <string.h>

#include "noshi_tl_ids.h"

static int is_vec(const noshi_tl_value *v) {
    return v && v->kind == NOSHI_TL_V_VEC;
}

/* a string cut at a character boundary so a long label never ends in half a sequence */
static void copy_cut(char *dst, size_t cap, const uint8_t *data, size_t len) {
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static void copy_field(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return;
    copy_cut(dst, cap, data, len);
}

/* stores a string in the pool; false when it does not fit whole, since a cut address would open the wrong page */
static int pool_put(noshi_markup *m, noshi_markup_button *b, const uint8_t *data, size_t len) {
    if (m->pool_len + len + 1 > sizeof(m->pool) || len > 0xffffu) return 0;
    memcpy(m->pool + m->pool_len, data, len);
    m->pool[m->pool_len + len] = 0;
    b->arg_offset = m->pool_len;
    b->arg_length = (uint16_t)len;
    m->pool_len = (uint16_t)(m->pool_len + len + 1);
    return 1;
}

static int pool_field(noshi_markup *m, noshi_markup_button *b, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return 0;
    return pool_put(m, b, data, len);
}

static uint8_t want_of(const noshi_tl_value *object, const char *field) {
    const noshi_tl_value *v = noshi_tl_get(object, field);
    if (noshi_tl_is(v, NOSHI_TL_ID_boolTrue)) return NOSHI_WANT_YES;
    if (v && v->kind == NOSHI_TL_V_OBJ) return NOSHI_WANT_NO;
    return NOSHI_WANT_ANY;
}

static void read_peer_type(const noshi_tl_value *type, noshi_markup_button *b) {
    if (noshi_tl_is(type, NOSHI_TL_ID_requestPeerTypeUser)) {
        b->choice = NOSHI_CHOICE_USER;
        b->want_bot = want_of(type, "bot");
        b->want_premium = want_of(type, "premium");
    } else if (noshi_tl_is(type, NOSHI_TL_ID_requestPeerTypeChat)) {
        b->choice = NOSHI_CHOICE_GROUP;
        b->want_creator = noshi_tl_has(type, "creator") ? NOSHI_WANT_YES : NOSHI_WANT_ANY;
        b->want_username = want_of(type, "has_username");
        b->want_forum = want_of(type, "forum");
    } else if (noshi_tl_is(type, NOSHI_TL_ID_requestPeerTypeBroadcast)) {
        b->choice = NOSHI_CHOICE_CHANNEL;
        b->want_creator = noshi_tl_has(type, "creator") ? NOSHI_WANT_YES : NOSHI_WANT_ANY;
        b->want_username = want_of(type, "has_username");
    } else if (noshi_tl_is(type, NOSHI_TL_ID_requestPeerTypeCreateBot)) {
        b->choice = NOSHI_CHOICE_CREATE_BOT;
    } else {
        b->kind = NOSHI_BUTTON_DISABLED;
    }
}

/* the part of a button that its type constructor decides, for a reply keyboard */
static void read_keyboard_type(noshi_markup_button *b, const noshi_tl_value *type) {
    b->kind = NOSHI_BUTTON_DISABLED;
    if (noshi_tl_is(type, NOSHI_TL_ID_buttonTypeDefault)) {
        b->kind = NOSHI_BUTTON_TEXT;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_buttonTypeRequestPhone)) {
        b->kind = NOSHI_BUTTON_REQUEST_PHONE;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_buttonTypeRequestGeoLocation)) {
        b->kind = NOSHI_BUTTON_REQUEST_GEO;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_buttonTypeRequestPoll)) {
        b->kind = NOSHI_BUTTON_REQUEST_POLL;
        b->quiz = want_of(type, "quiz");
    } else if (noshi_tl_is(type, NOSHI_TL_ID_buttonTypeRequestPeer)) {
        b->kind = NOSHI_BUTTON_REQUEST_PEER;
        b->max_quantity = 1;
        if (noshi_tl_get_i32(type, "button_id", &b->button_id) != NOSHI_OK) {
            b->kind = NOSHI_BUTTON_DISABLED;
            return;
        }
        {
            int32_t quantity = 1;
            noshi_tl_get_i32(type, "max_quantity", &quantity);
            b->max_quantity = (uint8_t)(quantity < 1 ? 1 : quantity > 10 ? 10 : quantity);
        }
        read_peer_type(noshi_tl_get(type, "peer_type"), b);
    }
}

static void read_inline_type(noshi_markup *m, noshi_markup_button *b, const noshi_tl_value *type) {
    b->kind = NOSHI_BUTTON_DISABLED;
    if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeUrl)) {
        b->kind = NOSHI_BUTTON_URL;
        if (!pool_field(m, b, type, "url")) b->kind = NOSHI_BUTTON_DISABLED;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeCallback)) {
        const uint8_t *data;
        size_t len;
        if (noshi_tl_get_bytes(type, "data", &data, &len) != NOSHI_OK || len > NOSHI_MARKUP_DATA_MAX) return;
        b->kind = NOSHI_BUTTON_CALLBACK;
        b->password = noshi_tl_has(type, "requires_password") ? 1 : 0;
        b->data_len = (uint8_t)len;
        if (len) memcpy(b->data, data, len);
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeUrlAuth)) {
        b->kind = NOSHI_BUTTON_URL_AUTH;
        if (noshi_tl_get_i32(type, "button_id", &b->button_id) != NOSHI_OK || !pool_field(m, b, type, "url"))
            b->kind = NOSHI_BUTTON_DISABLED;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeSwitchInline)) {
        b->kind = NOSHI_BUTTON_SWITCH_INLINE;
        b->same_peer = noshi_tl_has(type, "same_peer") ? 1 : 0;
        if (!pool_field(m, b, type, "query")) b->kind = NOSHI_BUTTON_DISABLED;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeGame)) {
        b->kind = NOSHI_BUTTON_GAME;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeBuy)) {
        b->kind = NOSHI_BUTTON_BUY;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeCopy)) {
        b->kind = NOSHI_BUTTON_COPY;
        if (!pool_field(m, b, type, "copy_text")) b->kind = NOSHI_BUTTON_DISABLED;
    } else if (noshi_tl_is(type, NOSHI_TL_ID_inlineButtonTypeUserProfile)) {
        b->kind = NOSHI_BUTTON_USER_PROFILE;
        if (noshi_tl_get_i64(type, "user_id", &b->user_id) != NOSHI_OK || b->user_id <= 0) b->kind = NOSHI_BUTTON_DISABLED;
    }
}

static void read_style(const noshi_tl_value *button, noshi_markup_button *b) {
    const noshi_tl_value *style = noshi_tl_get(button, "style");
    if (!noshi_tl_is(style, NOSHI_TL_ID_keyboardButtonStyle)) return;
    if (noshi_tl_has(style, "bg_danger")) b->style = NOSHI_BUTTON_STYLE_DANGER;
    else if (noshi_tl_has(style, "bg_success")) b->style = NOSHI_BUTTON_STYLE_SUCCESS;
    else if (noshi_tl_has(style, "bg_primary")) b->style = NOSHI_BUTTON_STYLE_PRIMARY;
    noshi_tl_get_i64(style, "icon", &b->icon);
}

static void read_rows(noshi_markup *m, const noshi_tl_value *rows, int inline_buttons) {
    uint32_t r, i;
    if (!is_vec(rows)) return;
    for (r = 0; r < rows->u.vec.count && m->row_count < NOSHI_MARKUP_ROWS_MAX; ++r) {
        const noshi_tl_value *buttons = noshi_tl_get(rows->u.vec.items[r], "buttons");
        uint8_t in_row = 0;
        if (!is_vec(buttons)) continue;
        for (i = 0; i < buttons->u.vec.count && in_row < NOSHI_MARKUP_ROW_MAX && m->button_count < NOSHI_MARKUP_BUTTONS_MAX; ++i) {
            const noshi_tl_value *button = buttons->u.vec.items[i];
            noshi_markup_button *b = &m->buttons[m->button_count];
            const noshi_tl_value *type;
            if (!noshi_tl_is(button, inline_buttons ? NOSHI_TL_ID_keyboardInlineButton : NOSHI_TL_ID_keyboardButton)) continue;
            memset(b, 0, sizeof(*b));
            copy_field(b->text, sizeof(b->text), button, "text");
            read_style(button, b);
            type = noshi_tl_get(button, "type");
            if (inline_buttons) read_inline_type(m, b, type);
            else read_keyboard_type(b, type);
            ++m->button_count;
            ++in_row;
        }
        if (in_row) m->row_size[m->row_count++] = in_row;
    }
}

noshi_status noshi_markup_read(const noshi_tl_value *markup, noshi_markup *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!markup) return NOSHI_OK;
    if (markup->kind != NOSHI_TL_V_OBJ) return NOSHI_E_MALFORMED;
    if (noshi_tl_is(markup, NOSHI_TL_ID_replyKeyboardHide)) {
        out->kind = NOSHI_MARKUP_HIDE;
        out->selective = noshi_tl_has(markup, "selective") ? 1 : 0;
        return NOSHI_OK;
    }
    if (noshi_tl_is(markup, NOSHI_TL_ID_replyKeyboardForceReply)) {
        out->kind = NOSHI_MARKUP_FORCE_REPLY;
        out->single_use = noshi_tl_has(markup, "single_use") ? 1 : 0;
        out->selective = noshi_tl_has(markup, "selective") ? 1 : 0;
        copy_field(out->placeholder, sizeof(out->placeholder), markup, "placeholder");
        return NOSHI_OK;
    }
    if (noshi_tl_is(markup, NOSHI_TL_ID_replyKeyboardMarkup)) {
        out->kind = NOSHI_MARKUP_KEYBOARD;
        out->resize = noshi_tl_has(markup, "resize") ? 1 : 0;
        out->single_use = noshi_tl_has(markup, "single_use") ? 1 : 0;
        out->selective = noshi_tl_has(markup, "selective") ? 1 : 0;
        out->persistent = noshi_tl_has(markup, "persistent") ? 1 : 0;
        copy_field(out->placeholder, sizeof(out->placeholder), markup, "placeholder");
        read_rows(out, noshi_tl_get(markup, "rows"), 0);
        if (!out->button_count) out->kind = NOSHI_MARKUP_NONE;
        return NOSHI_OK;
    }
    if (noshi_tl_is(markup, NOSHI_TL_ID_replyInlineMarkup)) {
        out->kind = NOSHI_MARKUP_INLINE;
        read_rows(out, noshi_tl_get(markup, "rows"), 1);
        if (!out->button_count) out->kind = NOSHI_MARKUP_NONE;
        return NOSHI_OK;
    }
    return NOSHI_E_UNSUPPORTED;
}

const char *noshi_markup_arg(const noshi_markup *markup, const noshi_markup_button *button) {
    if (!markup || !button || button->arg_length == 0) return "";
    return markup->pool + button->arg_offset;
}

static double round_half_up(double v) {
    return floor(v + 0.5);
}

noshi_status noshi_markup_layout(const uint8_t *row_size, size_t row_count, double width, double row_height, double gap,
                                     noshi_rect *frames, size_t cap, double *height) {
    size_t at = 0, r, total = 0;
    if (height) *height = 0;
    if (!frames || !height || (row_count && !row_size) || !(width > 0) || !(row_height > 0) || gap < 0) return NOSHI_E_ARG;
    for (r = 0; r < row_count; ++r) {
        if (row_size[r] == 0) return NOSHI_E_MALFORMED;
        total += row_size[r];
    }
    if (cap < total) return NOSHI_E_ARG;
    for (r = 0; r < row_count; ++r) {
        unsigned n = row_size[r], k;
        double y = (double)r * (row_height + gap);
        double unit = (width - gap * (double)(n - 1)) / (double)n;
        if (!(unit > 0)) return NOSHI_E_LIMIT;
        for (k = 0; k < n; ++k) {
            double left = round_half_up((double)k * (unit + gap));
            double right = round_half_up((double)k * (unit + gap) + unit);
            frames[at].x = left;
            frames[at].y = y;
            frames[at].width = right - left;
            frames[at].height = row_height;
            ++at;
        }
    }
    if (row_count) *height = (double)row_count * row_height + (double)(row_count - 1) * gap;
    return NOSHI_OK;
}
