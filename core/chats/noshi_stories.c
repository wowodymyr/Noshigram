#include "noshi_stories.h"

#include <string.h>

#include "noshi_store.h"
#include "noshi_tl_ids.h"

/* a story fills the screen, so its photo is read near 1280 px, where a message bubble takes 320 px */
#define STORY_PHOTO_TARGET 1280

static void copy_caption(char *dst, size_t cap, const noshi_tl_value *item) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (noshi_tl_get_bytes(item, "caption", &data, &len) != NOSHI_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

noshi_status noshi_story_read(const noshi_tl_value *item, noshi_story_row *out) {
    const noshi_tl_value *views;
    int32_t value;
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!item) return NOSHI_E_MALFORMED;
    if (noshi_tl_is(item, NOSHI_TL_ID_storyItemDeleted)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(item, NOSHI_TL_ID_storyItem) && !noshi_tl_is(item, NOSHI_TL_ID_storyItemSkipped))
        return NOSHI_E_MALFORMED;
    if (noshi_tl_get_i32(item, "id", &out->id) != NOSHI_OK || out->id <= 0 ||
        noshi_tl_get_i32(item, "date", &out->date) != NOSHI_OK ||
        noshi_tl_get_i32(item, "expire_date", &out->expire_date) != NOSHI_OK) {
        memset(out, 0, sizeof(*out));
        return NOSHI_E_MALFORMED;
    }
    out->close_friends = noshi_tl_has(item, "close_friends") ? 1 : 0;
    if (noshi_tl_is(item, NOSHI_TL_ID_storyItemSkipped)) {
        out->skipped = 1;
        return NOSHI_OK;
    }
    out->pinned = noshi_tl_has(item, "pinned") ? 1 : 0;
    out->out = noshi_tl_has(item, "out") ? 1 : 0;
    out->edited = noshi_tl_has(item, "edited") ? 1 : 0;
    out->noforwards = noshi_tl_has(item, "noforwards") ? 1 : 0;
    out->contacts = noshi_tl_has(item, "contacts") ? 1 : 0;
    out->selected = noshi_tl_has(item, "selected_contacts") ? 1 : 0;
    noshi_media_classify_sized(noshi_tl_get(item, "media"), STORY_PHOTO_TARGET, &out->media);
    if (noshi_tl_has(item, "music")) noshi_document_read(noshi_tl_get(item, "music"), &out->music);
    copy_caption(out->caption, sizeof(out->caption), item);
    views = noshi_tl_get(item, "views");
    if (views && noshi_tl_get_i32(views, "views_count", &value) == NOSHI_OK && value > 0) out->views = value;
    if (views && noshi_tl_get_i32(views, "reactions_count", &value) == NOSHI_OK && value > 0) out->reactions = value;
    if (noshi_tl_has(item, "sent_reaction") &&
        noshi_reaction_parse(noshi_tl_get(item, "sent_reaction"), &out->reaction) == NOSHI_OK) out->reacted = 1;
    return NOSHI_OK;
}

/* the story list of one poster: the live count, the unseen ones and the first of them */
static noshi_status read_peer_stories(const noshi_tl_value *entry, const noshi_tl_value *users, const noshi_tl_value *chats,
                                        int64_t self_id, noshi_story_peer *peer, noshi_story_row *rows, size_t cap,
                                        size_t *count) {
    const noshi_tl_value *list;
    noshi_peer who;
    uint32_t i;
    size_t n = 0;
    memset(peer, 0, sizeof(*peer));
    if (!noshi_tl_is(entry, NOSHI_TL_ID_peerStories) || noshi_peer_from_tl(noshi_tl_get(entry, "peer"), &who) != NOSHI_OK ||
        (who.kind != 1 && who.kind != 3) || who.id <= 0 || noshi_tl_get_vec(entry, "stories", &list) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    if (list->u.vec.count > NOSHI_STORIES_MAX) return NOSHI_E_LIMIT;
    if (noshi_tl_has(entry, "max_read_id") && (noshi_tl_get_i32(entry, "max_read_id", &peer->max_read_id) != NOSHI_OK ||
                                                 peer->max_read_id < 0)) return NOSHI_E_MALFORMED;
    peer->owner.peer_kind = who.kind;
    peer->owner.peer_id = who.id;
    noshi_dialog_peer_read(&peer->owner, users, chats, self_id);
    for (i = 0; i < list->u.vec.count; ++i) {
        noshi_story_row row;
        noshi_status status = noshi_story_read(list->u.vec.items[i], &row);
        /* a deleted or malformed item drops out; the rest of the poster's stories stay */
        if (status != NOSHI_OK) continue;
        ++peer->count;
        if (row.date > peer->newest_date) peer->newest_date = row.date;
        if (row.id > peer->max_read_id) {
            ++peer->unread;
            if (!peer->first_unread_id || row.id < peer->first_unread_id) peer->first_unread_id = row.id;
            if (row.close_friends) peer->close_friends = 1;
        }
        if (rows && n < cap) rows[n++] = row;
    }
    if (count) *count = n;
    return NOSHI_OK;
}

noshi_status noshi_story_peers_parse(const noshi_tl_value *answer, int64_t self_id, noshi_story_peer *peers,
                                         size_t cap, size_t *count, int *more) {
    const noshi_tl_value *list, *users, *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (more) *more = 0;
    if (!peers || !count || !cap) return NOSHI_E_ARG;
    if (noshi_tl_is(answer, NOSHI_TL_ID_stories_allStoriesNotModified)) return NOSHI_E_NOTFOUND;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_stories_allStories) ||
        noshi_tl_get_vec(answer, "peer_stories", &list) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (list->u.vec.count > NOSHI_STORY_PEERS_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        noshi_story_peer peer;
        noshi_status status = read_peer_stories(list->u.vec.items[i], users, chats, self_id, &peer, NULL, 0, NULL);
        /* one odd poster must not hide the strip */
        if (status != NOSHI_OK || !peer.count || peer.owner.deleted || !peer.owner.title[0]) continue;
        peers[n++] = peer;
    }
    *count = n;
    if (more) *more = noshi_tl_has(answer, "has_more") ? 1 : 0;
    return NOSHI_OK;
}

noshi_status noshi_story_peer_parse(const noshi_tl_value *answer, int64_t self_id, noshi_story_peer *peer,
                                        noshi_story_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *users, *chats;
    if (count) *count = 0;
    if (!peer || !rows || !count || !cap) return NOSHI_E_ARG;
    memset(peer, 0, sizeof(*peer));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_stories_peerStories) ||
        noshi_tl_get_vec(answer, "users", &users) != NOSHI_OK ||
        noshi_tl_get_vec(answer, "chats", &chats) != NOSHI_OK) return NOSHI_E_MALFORMED;
    return read_peer_stories(noshi_tl_get(answer, "stories"), users, chats, self_id, peer, rows, cap, count);
}

noshi_status noshi_stories_parse(const noshi_tl_value *answer, noshi_story_row *rows, size_t cap, size_t *count) {
    const noshi_tl_value *list;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || !cap) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_stories_stories) || noshi_tl_get_vec(answer, "stories", &list) != NOSHI_OK)
        return NOSHI_E_MALFORMED;
    if (list->u.vec.count > NOSHI_STORIES_MAX) return NOSHI_E_LIMIT;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        if (noshi_story_read(list->u.vec.items[i], &rows[n]) == NOSHI_OK) ++n;
    }
    *count = n;
    return NOSHI_OK;
}

noshi_status noshi_story_all_request(noshi_arena *arena, int next, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status = NOSHI_OK;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "stories.getAllStories");
    if (!request) return NOSHI_E_NOMEM;
    if (next) status = noshi_tl_set_flag(request, "next");
    if (status == NOSHI_OK) *out = request;
    return status;
}

/* a request whose first field is the poster */
static noshi_status peer_request(noshi_arena *arena, const char *name, const noshi_peer_ref *peer, noshi_tl_value **request) {
    noshi_tl_value *input;
    noshi_status status;
    *request = NULL;
    if (!arena) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, peer, &input);
    if (status != NOSHI_OK) return status;
    *request = noshi_tl_new_obj(arena, name);
    if (!*request) return NOSHI_E_NOMEM;
    return noshi_tl_set(*request, "peer", input);
}

noshi_status noshi_story_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    status = peer_request(arena, "stories.getPeerStories", peer, &request);
    *out = status == NOSHI_OK ? request : NULL;
    return status;
}

static noshi_status ids_request(noshi_arena *arena, const char *name, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                  noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    size_t i;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!ids || !count || count > NOSHI_STORIES_MAX) return NOSHI_E_ARG;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return NOSHI_E_ARG;
    status = peer_request(arena, name, peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_ids_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                         noshi_tl_value **out) {
    return ids_request(arena, "stories.getStoriesByID", peer, ids, count, out);
}

noshi_status noshi_story_views_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                           noshi_tl_value **out) {
    return ids_request(arena, "stories.incrementStoryViews", peer, ids, count, out);
}

noshi_status noshi_story_viewers_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t story_id, const char *offset, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || story_id <= 0 || (offset && strlen(offset) >= NOSHI_STORY_VIEWERS_OFFSET_MAX)) return NOSHI_E_ARG;
    status = peer_request(arena, "stories.getStoryViewsList", peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "id", story_id);
    /* the offset is a required field; an empty one asks for the first page */
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "offset", offset ? offset : "");
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", NOSHI_STORY_VIEWERS_PAGE);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_viewers_parse(const noshi_tl_value *answer, noshi_story_viewer *rows, size_t capacity, size_t *count, char *next, size_t next_capacity,
                                           int32_t *total, int32_t *reactions) {
    const noshi_tl_value *views;
    const uint8_t *offset;
    size_t length, kept = 0;
    if (count) *count = 0;
    if (next && next_capacity) next[0] = 0;
    if (total) *total = 0;
    if (reactions) *reactions = 0;
    if (!rows || !capacity || !count || !next || !next_capacity) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_stories_storyViewsList) || noshi_tl_get_vec(answer, "views", &views) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (views->u.vec.count > capacity) return NOSHI_E_LIMIT;
    if (total) noshi_tl_get_i32(answer, "views_count", total);
    if (reactions) noshi_tl_get_i32(answer, "reactions_count", reactions);
    if (noshi_tl_has(answer, "next_offset")) {
        if (noshi_tl_get_bytes(answer, "next_offset", &offset, &length) != NOSHI_OK || !offset || length >= next_capacity || length >= NOSHI_STORY_VIEWERS_OFFSET_MAX ||
            memchr(offset, 0, length)) return NOSHI_E_MALFORMED;
        memcpy(next, offset, length);
        next[length] = 0;
    }
    for (uint32_t i = 0; i < views->u.vec.count; ++i) {
        const noshi_tl_value *item = views->u.vec.items[i];
        noshi_story_viewer row;
        memset(&row, 0, sizeof(row));
        /* only a plain view names a user; forwards and reposts name a message or a story */
        if (!noshi_tl_is(item, NOSHI_TL_ID_storyView)) continue;
        if (noshi_tl_get_i64(item, "user_id", &row.user_id) != NOSHI_OK || row.user_id <= 0 || noshi_tl_get_i32(item, "date", &row.date) != NOSHI_OK) {
            next[0] = 0;
            return NOSHI_E_MALFORMED;
        }
        row.blocked = noshi_tl_has(item, "blocked") ? 1 : 0;
        if (noshi_tl_has(item, "reaction") && noshi_reaction_parse(noshi_tl_get(item, "reaction"), &row.reaction) == NOSHI_OK) row.reacted = 1;
        rows[kept++] = row;
    }
    *count = kept;
    return NOSHI_OK;
}

noshi_status noshi_story_read_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t max_id, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (max_id <= 0) return NOSHI_E_ARG;
    status = peer_request(arena, "stories.readStories", peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "max_id", max_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

static noshi_status page_request(noshi_arena *arena, const char *name, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                    noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (offset_id < 0 || limit < 1 || limit > NOSHI_STORIES_MAX) return NOSHI_E_ARG;
    status = peer_request(arena, name, peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_pinned_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                            noshi_tl_value **out) {
    return page_request(arena, "stories.getPinnedStories", peer, offset_id, limit, out);
}

noshi_status noshi_story_archive_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                             noshi_tl_value **out) {
    return page_request(arena, "stories.getStoriesArchive", peer, offset_id, limit, out);
}

noshi_status noshi_story_react_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id,
                                           const noshi_reaction *reaction, noshi_tl_value **out) {
    noshi_tl_value *request, *value;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (id <= 0) return NOSHI_E_ARG;
    status = peer_request(arena, "stories.sendReaction", peer, &request);
    if (status != NOSHI_OK) return status;
    if (reaction) {
        status = noshi_reaction_build(arena, reaction, &value);
    } else {
        value = noshi_tl_new_obj(arena, "reactionEmpty");
        status = value ? NOSHI_OK : NOSHI_E_NOMEM;
    }
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "story_id", id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reaction", value);
    if (status == NOSHI_OK && reaction) status = noshi_tl_set_flag(request, "add_to_recent");
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_reply_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t story_id, const char *text,
                                           int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *reply, *reply_peer;
    noshi_status status;
    if (!out) return NOSHI_E_ARG;
    *out = NULL;
    if (!arena || story_id <= 0) return NOSHI_E_ARG;
    status = noshi_send_text_request(arena, peer, text, NULL, 0, random_id, &request);
    if (status != NOSHI_OK) return status;
    status = noshi_input_peer(arena, peer, &reply_peer);
    reply = noshi_tl_new_obj(arena, "inputReplyToStory");
    if (status == NOSHI_OK && !reply) status = NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set(reply, "peer", reply_peer);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, reply, "story_id", story_id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "reply_to", reply);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_forward_request(noshi_arena *arena, const noshi_peer_ref *target, const noshi_peer_ref *owner, int32_t story_id,
                                             int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input, *media, *story_peer;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !target || !owner || !out || story_id <= 0 || random_id == 0) return NOSHI_E_ARG;
    status = noshi_input_peer(arena, target, &input);
    if (status == NOSHI_OK) status = noshi_input_peer(arena, owner, &story_peer);
    if (status != NOSHI_OK) return status;
    media = noshi_tl_new_obj(arena, "inputMediaStory");
    request = noshi_tl_new_obj(arena, "messages.sendMedia");
    if (!media || !request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(media, "peer", story_peer);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, media, "id", story_id);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", input);
    if (status == NOSHI_OK) status = noshi_set_topic_reply(arena, request, target);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "message", "");
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_send_photo_request(noshi_arena *arena, noshi_tl_value *file, int64_t random_id, noshi_tl_value **out) {
    noshi_tl_value *request, *peer, *media, *rules, *rule;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !file || !out || random_id == 0) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "stories.sendStory");
    peer = noshi_tl_new_obj(arena, "inputPeerSelf");
    media = noshi_tl_new_obj(arena, "inputMediaUploadedPhoto");
    rule = noshi_tl_new_obj(arena, "inputPrivacyValueAllowAll");
    rules = noshi_tl_new_vec(arena, 1);
    if (!request || !peer || !media || !rule || !rules) return NOSHI_E_NOMEM;
    status = noshi_tl_vec_set(rules, 0, rule);
    if (status == NOSHI_OK) status = noshi_tl_set(media, "file", file);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "peer", peer);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "media", media);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "privacy_rules", rules);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "period", NOSHI_STORY_PERIOD);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "random_id", random_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_story_privacy noshi_story_row_privacy(const noshi_story_row *row) {
    if (!row) return NOSHI_STORY_EVERYONE;
    if (row->close_friends) return NOSHI_STORY_CLOSE_FRIENDS;
    if (row->contacts) return NOSHI_STORY_CONTACTS;
    return NOSHI_STORY_EVERYONE;
}

/* the rule list of an audience: the base rule (none for a chosen list), the people the choice allows, and the people it leaves out */
static noshi_status user_rule(noshi_arena *arena, const char *name, const noshi_story_user *users, size_t count, noshi_tl_value **out) {
    noshi_tl_value *rule, *list;
    noshi_status status;
    rule = noshi_tl_new_obj(arena, name);
    list = noshi_tl_new_vec(arena, (uint32_t)count);
    if (!rule || !list) return NOSHI_E_NOMEM;
    for (size_t i = 0; i < count; ++i) {
        noshi_tl_value *user = noshi_tl_new_obj(arena, "inputUser");
        if (!user) return NOSHI_E_NOMEM;
        status = noshi_tl_set_i64(arena, user, "user_id", users[i].id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, user, "access_hash", users[i].access_hash);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, (uint32_t)i, user);
        if (status != NOSHI_OK) return status;
    }
    status = noshi_tl_set(rule, "users", list);
    if (status == NOSHI_OK) *out = rule;
    return status;
}

static noshi_status audience_rules(noshi_arena *arena, const noshi_story_audience *audience, noshi_tl_value **out) {
    static const char *const names[] = {"inputPrivacyValueAllowAll", "inputPrivacyValueAllowContacts", "inputPrivacyValueAllowCloseFriends"};
    noshi_tl_value *rules, *rule;
    noshi_status status;
    uint32_t total = 0, at = 0;
    *out = NULL;
    if (!audience || (int)audience->base < 0 || (int)audience->base > NOSHI_STORY_SELECTED) return NOSHI_E_ARG;
    if (audience->allow_count > NOSHI_STORY_USERS_MAX || audience->deny_count > NOSHI_STORY_USERS_MAX) return NOSHI_E_LIMIT;
    /* a chosen list needs people; the others may leave some out, and the close friends have nobody to leave out */
    if (audience->base == NOSHI_STORY_SELECTED && !audience->allow_count) return NOSHI_E_ARG;
    if (audience->base == NOSHI_STORY_SELECTED) total = 1;
    else total = 1 + (audience->deny_count && audience->base != NOSHI_STORY_CLOSE_FRIENDS ? 1u : 0u);
    rules = noshi_tl_new_vec(arena, total);
    if (!rules) return NOSHI_E_NOMEM;
    if (audience->base == NOSHI_STORY_SELECTED) {
        status = user_rule(arena, "inputPrivacyValueAllowUsers", audience->allow, audience->allow_count, &rule);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(rules, at++, rule);
    } else {
        rule = noshi_tl_new_obj(arena, names[audience->base]);
        if (!rule) return NOSHI_E_NOMEM;
        status = noshi_tl_vec_set(rules, at++, rule);
        if (status == NOSHI_OK && audience->deny_count && audience->base != NOSHI_STORY_CLOSE_FRIENDS) {
            status = user_rule(arena, "inputPrivacyValueDisallowUsers", audience->deny, audience->deny_count, &rule);
            if (status == NOSHI_OK) status = noshi_tl_vec_set(rules, at++, rule);
        }
    }
    if (status == NOSHI_OK) *out = rules;
    return status;
}

/* the old calls take only a base choice */
static void base_audience(noshi_story_audience *audience, noshi_story_privacy privacy) {
    memset(audience, 0, sizeof(*audience));
    audience->base = privacy;
}

noshi_status noshi_story_publish_photo_audience_request(noshi_arena *arena, noshi_tl_value *file, int64_t random_id, const char *caption,
                                                            const noshi_story_audience *audience, noshi_tl_value **out) {
    noshi_tl_value *request, *rules = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || (caption && strlen(caption) > NOSHI_STORY_CAPTION_MAX - 1)) return NOSHI_E_ARG;
    status = audience_rules(arena, audience, &rules);
    if (status != NOSHI_OK) return status;
    status = noshi_story_send_photo_request(arena, file, random_id, &request);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "privacy_rules", rules);
    if (status == NOSHI_OK && caption && caption[0]) status = noshi_tl_set_str(arena, request, "caption", caption);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_publish_photo_request(noshi_arena *arena, noshi_tl_value *file, int64_t random_id, const char *caption,
                                                   noshi_story_privacy privacy, noshi_tl_value **out) {
    noshi_story_audience audience;
    if (out) *out = NULL;
    if ((int)privacy < 0 || (int)privacy > NOSHI_STORY_CLOSE_FRIENDS) return NOSHI_E_ARG;
    base_audience(&audience, privacy);
    return noshi_story_publish_photo_audience_request(arena, file, random_id, caption, &audience, out);
}

noshi_status noshi_story_edit_audience_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, const char *caption, int set_audience,
                                                   const noshi_story_audience *audience, noshi_tl_value **out) {
    noshi_tl_value *request, *rules = NULL, *entities;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || id <= 0 || (caption && strlen(caption) > NOSHI_STORY_CAPTION_MAX - 1)) return NOSHI_E_ARG;
    if (set_audience) {
        status = audience_rules(arena, audience, &rules);
        if (status != NOSHI_OK) return status;
    }
    status = peer_request(arena, "stories.editStory", peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "id", id);
    if (status == NOSHI_OK && caption) {
        /* the caption and its entities share one flag, so the entities go with it, empty */
        entities = noshi_tl_new_vec(arena, 0);
        status = entities ? noshi_tl_set_str(arena, request, "caption", caption) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = noshi_tl_set(request, "entities", entities);
    }
    if (status == NOSHI_OK && rules) status = noshi_tl_set(request, "privacy_rules", rules);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_edit_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, const char *caption, int set_privacy,
                                          noshi_story_privacy privacy, noshi_tl_value **out) {
    noshi_story_audience audience;
    if (out) *out = NULL;
    if ((int)privacy < 0 || (int)privacy > NOSHI_STORY_CLOSE_FRIENDS) return NOSHI_E_ARG;
    base_audience(&audience, privacy);
    return noshi_story_edit_audience_request(arena, peer, id, caption, set_privacy, &audience, out);
}

noshi_status noshi_story_link_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out || id <= 0) return NOSHI_E_ARG;
    status = peer_request(arena, "stories.exportStoryLink", peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "id", id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_link_parse(const noshi_tl_value *answer, char *link, size_t cap) {
    const uint8_t *data;
    size_t len;
    if (link && cap) link[0] = 0;
    if (!link || cap < 2) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_exportedStoryLink) || noshi_tl_get_bytes(answer, "link", &data, &len) != NOSHI_OK || !len) return NOSHI_E_MALFORMED;
    if (len >= cap || len > 255) return NOSHI_E_LIMIT;
    memcpy(link, data, len);
    link[len] = 0;
    return NOSHI_OK;
}

noshi_status noshi_story_hide_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, int hidden, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    status = peer_request(arena, "stories.togglePeerStoriesHidden", peer, &request);
    if (status == NOSHI_OK) status = noshi_tl_set(request, "hidden", noshi_tl_new_obj(arena, hidden ? "boolTrue" : "boolFalse"));
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_story_delete_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                            noshi_tl_value **out) {
    return ids_request(arena, "stories.deleteStories", peer, ids, count, out);
}

noshi_status noshi_story_pin_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count, int pinned,
                                         noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status = ids_request(arena, "stories.togglePinned", peer, ids, count, &request);
    if (out) *out = NULL;
    if (!out) return NOSHI_E_ARG;
    if (status == NOSHI_OK) status = noshi_tl_set(request, "pinned", noshi_tl_new_obj(arena, pinned ? "boolTrue" : "boolFalse"));
    if (status == NOSHI_OK) *out = request;
    return status;
}
