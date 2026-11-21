#ifndef NOSHI_BOOKMARKS_H
#define NOSHI_BOOKMARKS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

#define NOSHI_BOOKMARKS_MAX 200
#define NOSHI_BOOKMARK_TITLE_MAX 96
#define NOSHI_BOOKMARK_TEXT_MAX 120
#define NOSHI_BOOKMARKS_FILE_MAX (20u + NOSHI_BOOKMARKS_MAX * 252u)

/* a message the person marked to find again: where it is, enough to open its chat, and a line to recognise it by */
typedef struct noshi_bookmark {
    int32_t peer_kind;      /* 1 user, 2 chat, 3 channel */
    int64_t peer_id;
    int64_t peer_hash;      /* the access hash an input peer needs; zero for a basic group */
    int32_t dialog_kind;    /* noshi_dialog_kind of the chat, so the chat opens as the kind it is */
    int32_t message_id;
    int32_t date;           /* when the message was sent */
    int32_t added;          /* when it was bookmarked, unix seconds */
    char title[NOSHI_BOOKMARK_TITLE_MAX];     /* the chat's name, UTF-8 */
    char text[NOSHI_BOOKMARK_TEXT_MAX];       /* the start of the message, UTF-8, or the word for its media */
} noshi_bookmark;

/* newest first; the list holds at most NOSHI_BOOKMARKS_MAX and drops the oldest beyond it */
typedef struct noshi_bookmarks {
    size_t count;
    noshi_bookmark items[NOSHI_BOOKMARKS_MAX];
} noshi_bookmarks;

void noshi_bookmarks_init(noshi_bookmarks *list);
/* puts the entry first; one that is already there (same chat and message) is replaced and moves to the front
   instead of appearing twice */
noshi_status noshi_bookmarks_add(noshi_bookmarks *list, const noshi_bookmark *entry);
/* NOSHI_E_NOTFOUND when the message was not bookmarked */
noshi_status noshi_bookmarks_remove(noshi_bookmarks *list, int32_t peer_kind, int64_t peer_id, int32_t message_id);
int noshi_bookmarks_contains(const noshi_bookmarks *list, int32_t peer_kind, int64_t peer_id, int32_t message_id);

/* a file for one account: a header with its id, then the entries. cap must be NOSHI_BOOKMARKS_FILE_MAX or what the list needs */
noshi_status noshi_bookmarks_pack(const noshi_bookmarks *list, int64_t account_id, uint8_t *out, size_t cap, size_t *len);
/* NOSHI_E_MALFORMED for a file that is not whole or has an entry that add would refuse */
noshi_status noshi_bookmarks_unpack(const uint8_t *data, size_t len, int64_t account_id, noshi_bookmarks *out);

#endif
