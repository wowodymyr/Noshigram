#ifndef NOSHI_INVITE_H
#define NOSHI_INVITE_H

#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_tl.h"

#define NOSHI_INVITE_LINK_MAX 128
#define NOSHI_INVITE_TITLE_MAX 64
#define NOSHI_INVITES_PAGE 50
#define NOSHI_INVITES_MAX 100
/* the longest period and the largest number of joins the server takes for one link */
#define NOSHI_INVITE_LIMIT_MAX 99999

typedef struct noshi_invite {
    char link[NOSHI_INVITE_LINK_MAX];
    char title[NOSHI_INVITE_TITLE_MAX];
    uint8_t revoked;
    uint8_t permanent;          /* the link the chat was made with, which a new one does not replace unless it is revoked */
    uint8_t request_needed;     /* a join waits for an admin to accept it */
    int32_t date;
    int32_t start_date;         /* zero when the link is live from its creation */
    int32_t expire_date;        /* zero for a link that does not end */
    int32_t usage_limit;        /* zero for no limit */
    int32_t usage;
    int32_t requested;          /* joins waiting for approval */
    int64_t admin_id;
} noshi_invite;

/* what the editor sends: zero expire_date and usage_limit leave the link without that limit */
typedef struct noshi_invite_spec {
    int32_t expire_date;
    int32_t usage_limit;
    uint8_t request_needed;
    char title[NOSHI_INVITE_TITLE_MAX];
} noshi_invite_spec;

/* messages.getExportedChatInvites of this account's own links, the live ones or the revoked ones; offset_link empty on the first page and the last link of the
   page before on the next one */
noshi_status noshi_invite_list_request(noshi_arena *arena, const noshi_peer_ref *peer, int revoked, int32_t offset_date, const char *offset_link,
                                          noshi_tl_value **out);
noshi_status noshi_invite_list_parse(const noshi_tl_value *answer, noshi_invite *rows, size_t cap, size_t *count, int32_t *total);

noshi_status noshi_invite_create_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_invite_spec *spec, noshi_tl_value **out);
noshi_status noshi_invite_edit_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *link, const noshi_invite_spec *spec,
                                          noshi_tl_value **out);
noshi_status noshi_invite_revoke_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *link, noshi_tl_value **out);
noshi_status noshi_invite_delete_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *link, noshi_tl_value **out);
noshi_status noshi_invite_delete_revoked_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);

/* the link an edit, a creation or a revoke answers with; a revoke of the permanent link answers with the link that took its place in `replacement` when it is
   not NULL */
noshi_status noshi_invite_answer_parse(const noshi_tl_value *answer, noshi_invite *invite, noshi_invite *replacement, int *replaced);

#endif
