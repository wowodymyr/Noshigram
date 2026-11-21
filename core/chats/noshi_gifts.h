#ifndef NOSHI_GIFTS_H
#define NOSHI_GIFTS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_gift.h"
#include "noshi_messages.h"
#include "noshi_tl.h"

#define NOSHI_GIFTS_MAX 300
#define NOSHI_SAVED_GIFTS_MAX 50
#define NOSHI_GIFT_NOTE_MAX 256
#define NOSHI_GIFT_OFFSET_MAX 64

/* the fallback until the server's app configuration arrives */
#define NOSHI_GIFT_CONVERT_PERIOD_DEFAULT (7 * 86400)
noshi_status noshi_gift_convert_period_parse(const noshi_tl_value *answer, int32_t *seconds);

/* a gift on a profile: what was received, from whom, and what can be done with it */
typedef struct noshi_saved_gift {
    noshi_gift gift;
    int64_t from_id;            /* zero when the sender hid their name */
    noshi_person_row from_person; /* the sender as the answer carries them, id zero when the name is hidden or the user is missing */
    int32_t date;
    int32_t msg_id;             /* names the gift to the server on the profile of a user */
    uint8_t name_hidden;
    uint8_t unsaved;            /* hidden from the profile */
    uint8_t can_upgrade;
    uint8_t pinned;
    uint8_t refunded;
    int64_t convert_stars;
    int64_t upgrade_stars;      /* what the upgrade costs the receiver, zero when it was prepaid or is not offered */
    int64_t transfer_stars;     /* what handing a unique gift to someone costs, zero when free */
    int32_t can_transfer_at;    /* unix time from which a unique gift can be handed on */
    char from_name[NOSHI_PERSON_NAME_MAX];
    char note[NOSHI_GIFT_NOTE_MAX];
    noshi_entity note_entities[NOSHI_MESSAGE_ENTITIES_MAX];
    uint8_t note_entity_count;
    char note_urls[NOSHI_MESSAGE_URLS_MAX];
} noshi_saved_gift;

int noshi_gift_can_convert(const noshi_saved_gift *gift, int64_t now, int32_t period);

typedef struct noshi_saved_gift_page {
    int32_t total;
    char next_offset[NOSHI_GIFT_OFFSET_MAX];  /* empty on the last page */
} noshi_saved_gift_page;

/* a folder of the gifts on a profile, as the server keeps them: the gifts of a user or a channel are shown by folder, "all gifts" being no folder at all */
#define NOSHI_GIFT_COLLECTIONS_MAX 100
#define NOSHI_GIFT_COLLECTION_TITLE_MAX 64
/* the most gifts one request adds to or takes from a folder */
#define NOSHI_GIFT_COLLECTION_BATCH_MAX 50
typedef struct noshi_gift_collection {
    int32_t id;
    int32_t count;              /* how many gifts it holds */
    char title[NOSHI_GIFT_COLLECTION_TITLE_MAX];
} noshi_gift_collection;

/* one starGiftCollection, the answer of a create or an update; anything else is NOSHI_E_MALFORMED */
noshi_status noshi_gift_collection_read(const noshi_tl_value *value, noshi_gift_collection *out);
/* a payments.starGiftCollections answer in server order; a folder that cannot be read is skipped. starGiftCollectionsNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_gift_collections_parse(const noshi_tl_value *answer, noshi_gift_collection *rows, size_t cap, size_t *count);

/* a payments.starGifts answer in server order, the gifts that cannot be sold any more last; starGiftsNotModified is
   NOSHI_E_NOTFOUND. hash is what the next request sends to skip an unchanged catalog */
noshi_status noshi_gifts_parse(const noshi_tl_value *answer, noshi_gift *gifts, size_t cap, size_t *count, int32_t *hash);

/* a payments.savedStarGifts answer in server order; a gift that cannot be read is skipped */
noshi_status noshi_saved_gifts_parse(const noshi_tl_value *answer, noshi_saved_gift *rows, size_t cap, size_t *count,
                                         noshi_saved_gift_page *page);

/* the stars of a payments.starsStatus answer; an amount in toncoin is NOSHI_E_UNSUPPORTED */
noshi_status noshi_stars_balance_parse(const noshi_tl_value *answer, int64_t *stars);

/* the form and total of a paymentFormStarGift answer; any other form is NOSHI_E_UNSUPPORTED, this client pays in
   stars only */
noshi_status noshi_payment_form_parse(const noshi_tl_value *answer, int64_t *form_id, int64_t *stars);

/* a payments.paymentResult; a result that asks for a web verification is NOSHI_E_UNSUPPORTED */
noshi_status noshi_payment_result_check(const noshi_tl_value *answer);

/* requests, built in arena. limit is 1 to NOSHI_SAVED_GIFTS_MAX and offset is "" for the first page */
noshi_status noshi_gifts_request(noshi_arena *arena, int32_t hash, noshi_tl_value **out);
noshi_status noshi_saved_gifts_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *offset, int32_t limit,
                                           noshi_tl_value **out);
noshi_status noshi_stars_balance_request(noshi_arena *arena, noshi_tl_value **out);
/* the gifts of one folder: the request above with collection_id; the id must be positive */
noshi_status noshi_saved_gifts_in_collection_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t collection_id, const char *offset,
                                                         int32_t limit, noshi_tl_value **out);
/* the folders of a profile, and the changes the owner of the profile makes to them */
noshi_status noshi_gift_collections_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);
noshi_status noshi_gift_collection_create_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *title, const int32_t *msg_ids,
                                                      size_t count, noshi_tl_value **out);
/* a nil title keeps the name; adds and removes may be empty but not both, and the title may change alone */
noshi_status noshi_gift_collection_update_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t collection_id, const char *title,
                                                      const int32_t *add, size_t add_count, const int32_t *remove, size_t remove_count,
                                                      noshi_tl_value **out);
noshi_status noshi_gift_collection_delete_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t collection_id, noshi_tl_value **out);

/* the three invoices of a gift: buying one for a user, upgrading a received one, handing one on */
/* entities are the runs of note (custom emoji for Premium senders), offsets in UTF-16 units; none for plain text */
noshi_status noshi_gift_invoice_send(noshi_arena *arena, const noshi_peer_ref *peer, int64_t gift_id, const char *note,
                                         const noshi_send_entity *entities, size_t entity_count, int hide_name, int include_upgrade,
                                         noshi_tl_value **out);
noshi_status noshi_gift_invoice_upgrade(noshi_arena *arena, int32_t msg_id, int keep_details, noshi_tl_value **out);
noshi_status noshi_gift_invoice_transfer(noshi_arena *arena, int32_t msg_id, const noshi_peer_ref *to, noshi_tl_value **out);
/* the invoice that unlocks the paid media of one message */
noshi_status noshi_paid_media_invoice(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, noshi_tl_value **out);
/* payments.getPaymentForm and payments.sendStarsForm for an invoice made above */
noshi_status noshi_payment_form_request(noshi_arena *arena, noshi_tl_value *invoice, noshi_tl_value **out);
noshi_status noshi_payment_send_request(noshi_arena *arena, int64_t form_id, noshi_tl_value *invoice, noshi_tl_value **out);

/* what the receiver of a gift can do without paying */
noshi_status noshi_gift_save_request(noshi_arena *arena, int32_t msg_id, int unsave, noshi_tl_value **out);
noshi_status noshi_gift_convert_request(noshi_arena *arena, int32_t msg_id, noshi_tl_value **out);
/* free upgrade of a gift whose upgrade was prepaid, and the free transfer of a unique one */
noshi_status noshi_gift_upgrade_request(noshi_arena *arena, int32_t msg_id, int keep_details, noshi_tl_value **out);
noshi_status noshi_gift_transfer_request(noshi_arena *arena, int32_t msg_id, const noshi_peer_ref *to, noshi_tl_value **out);
noshi_status noshi_gift_pin_request(noshi_arena *arena, const int32_t *msg_ids, size_t count, noshi_tl_value **out);
/* account.updateEmojiStatus: the unique gift with this id worn after the name of the account, or, with zero, whatever status there is taken off */
noshi_status noshi_gift_wear_request(noshi_arena *arena, int64_t collectible_id, noshi_tl_value **out);

#endif
