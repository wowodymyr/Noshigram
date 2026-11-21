#include "noshi_folders.h"

noshi_status noshi_folder_title_build(noshi_arena *arena, const char *text, const noshi_send_entity *entities,
                                          size_t count, noshi_tl_value **out) {
    noshi_tl_value *title, *list = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !text || !out || (count && !entities) || count > NOSHI_MESSAGE_ENTITIES_MAX) return NOSHI_E_ARG;
    for (size_t i = 0; i < count; ++i)
        if (entities[i].kind != NOSHI_ENTITY_CUSTOM_EMOJI || entities[i].id <= 0) return NOSHI_E_ARG;
    status = noshi_send_entities_build(arena, text, entities, count, &list);
    if (status != NOSHI_OK) return status;
    title = noshi_tl_new_obj(arena, "textWithEntities");
    if (!list) list = noshi_tl_new_vec(arena, 0);
    if (!title || !list) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, title, "text", text);
    if (status == NOSHI_OK) status = noshi_tl_set(title, "entities", list);
    if (status == NOSHI_OK) *out = title;
    return status;
}

int noshi_folder_shift_emoji(size_t *offset, size_t length, size_t start, size_t removed, size_t inserted) {
    if (!offset || !length || length > SIZE_MAX - *offset || removed > SIZE_MAX - start) return 0;
    if (*offset + length <= start) return 1;
    if (*offset >= start + removed) {
        size_t base = *offset - removed;
        if (inserted > SIZE_MAX - base) return 0;
        *offset = base + inserted;
        return 1;
    }
    return 0;
}

int noshi_folder_scans_dialogs(uint32_t flags, int archived) {
    uint32_t categories = NOSHI_FOLDER_CONTACTS | NOSHI_FOLDER_NON_CONTACTS | NOSHI_FOLDER_GROUPS | NOSHI_FOLDER_CHANNELS | NOSHI_FOLDER_BOTS;
    return (flags & categories) != 0 && (!archived || !(flags & NOSHI_FOLDER_SKIP_ARCHIVED));
}

static size_t peer_index(const noshi_peer_ref *peers, size_t count, const noshi_dialog_row *dialog) {
    if (!peers || count > NOSHI_FOLDER_PEERS_MAX)
        return SIZE_MAX;
    for (size_t i = 0; i < count; ++i) {
        if ((peers[i].self && dialog->saved) || (!peers[i].self && peers[i].kind == dialog->peer_kind && peers[i].id == dialog->peer_id))
            return i;
    }
    return SIZE_MAX;
}

size_t noshi_folder_pin_index(const noshi_folder_rules *rules, const noshi_dialog_row *dialog) {
    if (!rules || !dialog)
        return SIZE_MAX;
    return peer_index(rules->pinned, rules->pinned_count, dialog);
}

int noshi_folder_contains(const noshi_folder_rules *rules, const noshi_dialog_row *dialog) {
    if (!rules || !dialog || dialog->folder || rules->included_count > NOSHI_FOLDER_PEERS_MAX || rules->excluded_count > NOSHI_FOLDER_PEERS_MAX ||
        rules->pinned_count > NOSHI_FOLDER_PEERS_MAX || (rules->included_count && !rules->included) || (rules->excluded_count && !rules->excluded) ||
        (rules->pinned_count && !rules->pinned))
        return 0;
    if (peer_index(rules->excluded, rules->excluded_count, dialog) != SIZE_MAX)
        return 0;
    if (peer_index(rules->included, rules->included_count, dialog) != SIZE_MAX || noshi_folder_pin_index(rules, dialog) != SIZE_MAX)
        return 1;
    if ((rules->flags & NOSHI_FOLDER_SKIP_ARCHIVED) && dialog->folder_id != 0)
        return 0;
    /* mentions keep a muted or otherwise read chat visible */
    if (!dialog->mentions) {
        if ((rules->flags & NOSHI_FOLDER_SKIP_MUTED) && dialog->muted)
            return 0;
        if ((rules->flags & NOSHI_FOLDER_SKIP_READ) && !dialog->unread_count && !dialog->unread_mark)
            return 0;
    }
    if (dialog->community)
        return (rules->flags & 31u) == 31u;
    switch (dialog->kind) {
    case NOSHI_DIALOG_USER:
        return (rules->flags & (dialog->contact || dialog->saved ? NOSHI_FOLDER_CONTACTS : NOSHI_FOLDER_NON_CONTACTS)) != 0;
    case NOSHI_DIALOG_BOT:
        return (rules->flags & NOSHI_FOLDER_BOTS) != 0;
    case NOSHI_DIALOG_GROUP:
        return (rules->flags & NOSHI_FOLDER_GROUPS) != 0;
    case NOSHI_DIALOG_CHANNEL:
        return (rules->flags & NOSHI_FOLDER_CHANNELS) != 0;
    default:
        return 0;
    }
}
