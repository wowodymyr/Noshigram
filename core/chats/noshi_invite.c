#include "noshi_invite.h"

#include <string.h>

#include "noshi_tl_ids.h"

static void copy_text(char *dst, size_t cap, const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static noshi_status admin_self(noshi_arena *arena, noshi_tl_value **out) {
    *out = noshi_tl_new_obj(arena, "inputUserSelf");
    return *out ? NOSHI_OK : NOSHI_E_NOMEM;
}

static noshi_status link_valid(const char *link) {
    size_t len = link ? strlen(link) : 0;
    return len > 0 && len < NOSHI_INVITE_LINK_MAX ? NOSHI_OK : NOSHI_E_ARG;
}

static noshi_status spec_valid(const noshi_invite_spec *spec) {
    if (!spec || spec->expire_date < 0 || spec->usage_limit < 0 || spec->usage_limit > NOSHI_INVITE_LIMIT_MAX) return NOSHI_E_ARG;
    /* a join that needs approval counts no uses, so the server refuses the two together */
    if (spec->request_needed && spec->usage_limit) return NOSHI_E_ARG;
    return memchr(spec->title, 0, sizeof(spec->title)) ? NOSHI_OK : NOSHI_E_ARG;
}

static noshi_status peer_input(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **input) {
    *input = NULL;
    if (!arena || !peer) return NOSHI_E_ARG;
    return noshi_input_peer(arena, peer, input);
}

noshi_status noshi_invite_list_request(noshi_arena *arena, const noshi_peer_ref *peer, int revoked, int32_t offset_date, const char *offset_link,
                                          noshi_tl_value **out) {
    noshi_tl_value *request, *input, *admin;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || offset_date < 0 || (offset_link && strlen(offset_link) >= NOSHI_INVITE_LINK_MAX)) return NOSHI_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status == NOSHI_OK) status = admin_self(arena, &admin);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.getExportedChatInvites");
    if (!request) return NOSHI_E_NOMEM;
    if (revoked) status = noshi_tl_set_flag(request, "revoked");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "admin_id", admin);
    if (status == NOSHI_OK && offset_link && offset_link[0]) {
        /* the server pages by the date and the link of the last one it sent, and wants both */
        status = noshi_tl_set_i32(arena, request, "offset_date", offset_date);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "offset_link", offset_link);
    }
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", NOSHI_INVITES_PAGE);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static noshi_status invite_read(const noshi_tl_value *value, noshi_invite *row) {
    memset(row, 0, sizeof(*row));
    /* a chatInvitePublicJoinRequests entry says people wait to join; it is no link */
    if (!value || !noshi_tl_is(value, NOSHI_TL_ID_chatInviteExported)) return NOSHI_E_UNSUPPORTED;
    copy_text(row->link, sizeof(row->link), value, "link");
    if (!row->link[0]) return NOSHI_E_MALFORMED;
    copy_text(row->title, sizeof(row->title), value, "title");
    row->revoked = noshi_tl_has(value, "revoked") ? 1 : 0;
    row->permanent = noshi_tl_has(value, "permanent") ? 1 : 0;
    row->request_needed = noshi_tl_has(value, "request_needed") ? 1 : 0;
    noshi_tl_get_i32(value, "date", &row->date);
    noshi_tl_get_i32(value, "start_date", &row->start_date);
    noshi_tl_get_i32(value, "expire_date", &row->expire_date);
    noshi_tl_get_i32(value, "usage_limit", &row->usage_limit);
    noshi_tl_get_i32(value, "usage", &row->usage);
    noshi_tl_get_i32(value, "requested", &row->requested);
    noshi_tl_get_i64(value, "admin_id", &row->admin_id);
    if (row->usage_limit < 0 || row->usage < 0 || row->requested < 0 || row->expire_date < 0) return NOSHI_E_MALFORMED;
    return NOSHI_OK;
}

noshi_status noshi_invite_list_parse(const noshi_tl_value *answer, noshi_invite *rows, size_t cap, size_t *count, int32_t *total) {
    const noshi_tl_value *list = NULL;
    size_t n = 0;
    uint32_t i;
    int32_t all = 0;
    if (count) *count = 0;
    if (total) *total = 0;
    if (!answer || !rows || !cap || !count || !total) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_exportedChatInvites) || noshi_tl_get_i32(answer, "count", &all) != NOSHI_OK || all < 0 ||
        noshi_tl_get_vec(answer, "invites", &list) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (list->u.vec.count > cap) return NOSHI_E_LIMIT;
    for (i = 0; i < list->u.vec.count; ++i) {
        noshi_status status = invite_read(list->u.vec.items[i], &rows[n]);
        if (status == NOSHI_E_UNSUPPORTED) continue;
        if (status != NOSHI_OK) {
            *count = 0;
            return status;
        }
        ++n;
    }
    *count = n;
    *total = all;
    return NOSHI_OK;
}

static noshi_status spec_apply(noshi_arena *arena, noshi_tl_value *request, const noshi_invite_spec *spec, int edit) {
    noshi_status status = NOSHI_OK;
    if (spec->expire_date > 0) status = noshi_tl_set_i32(arena, request, "expire_date", spec->expire_date);
    /* an edit that leaves a limit out would keep the old one, so zero is sent as zero there */
    if (status == NOSHI_OK && (spec->usage_limit > 0 || edit)) status = noshi_tl_set_i32(arena, request, "usage_limit", spec->usage_limit);
    if (status == NOSHI_OK && edit && spec->expire_date == 0) status = noshi_tl_set_i32(arena, request, "expire_date", 0);
    if (status == NOSHI_OK && spec->title[0]) status = noshi_tl_set_str(arena, request, "title", spec->title);
    else if (status == NOSHI_OK && edit) status = noshi_tl_set_str(arena, request, "title", "");
    return status;
}

noshi_status noshi_invite_create_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_invite_spec *spec, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || spec_valid(spec) != NOSHI_OK) return NOSHI_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.exportChatInvite");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK && spec->request_needed) status = noshi_tl_set_flag(request, "request_needed");
    if (status == NOSHI_OK) status = spec_apply(arena, request, spec, 0);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_invite_edit_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *link, const noshi_invite_spec *spec,
                                          noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || link_valid(link) != NOSHI_OK || spec_valid(spec) != NOSHI_OK) return NOSHI_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.editExportedChatInvite");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "link", link);
    if (status == NOSHI_OK) {
        noshi_tl_value *needed = noshi_tl_new_obj(arena, spec->request_needed ? "boolTrue" : "boolFalse");
        status = needed ? noshi_tl_set(request, "request_needed", needed) : NOSHI_E_NOMEM;
    }
    if (status == NOSHI_OK) status = spec_apply(arena, request, spec, 1);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_invite_revoke_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *link, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || link_valid(link) != NOSHI_OK) return NOSHI_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.editExportedChatInvite");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_flag(request, "revoked");
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "link", link);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_invite_delete_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *link, noshi_tl_value **out) {
    noshi_tl_value *request, *input;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || link_valid(link) != NOSHI_OK) return NOSHI_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.deleteExportedChatInvite");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "link", link);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_invite_delete_revoked_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *admin;
    noshi_status status;
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status == NOSHI_OK) status = admin_self(arena, &admin);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "messages.deleteRevokedExportedChatInvites");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "admin_id", admin);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_invite_answer_parse(const noshi_tl_value *answer, noshi_invite *invite, noshi_invite *replacement, int *replaced) {
    noshi_status status;
    if (replaced) *replaced = 0;
    if (!answer || !invite) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_chatInviteExported)) return invite_read(answer, invite) == NOSHI_OK ? NOSHI_OK : NOSHI_E_MALFORMED;
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_exportedChatInvite)) {
        status = invite_read(noshi_tl_get(answer, "invite"), invite);
        return status == NOSHI_OK ? NOSHI_OK : NOSHI_E_MALFORMED;
    }
    if (noshi_tl_is(answer, NOSHI_TL_ID_messages_exportedChatInviteReplaced)) {
        noshi_invite spare;
        status = invite_read(noshi_tl_get(answer, "invite"), invite);
        if (status == NOSHI_OK) status = invite_read(noshi_tl_get(answer, "new_invite"), replacement ? replacement : &spare);
        if (status != NOSHI_OK) return NOSHI_E_MALFORMED;
        if (replaced) *replaced = 1;
        return NOSHI_OK;
    }
    return NOSHI_E_MALFORMED;
}
