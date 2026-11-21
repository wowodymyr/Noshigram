#ifndef NOSHI_STORIES_H
#define NOSHI_STORIES_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_messages.h"
#include "noshi_reactions.h"
#include "noshi_tl.h"

#define NOSHI_STORY_PEERS_MAX 200
#define NOSHI_STORIES_MAX 100
#define NOSHI_STORY_CAPTION_MAX 1024

typedef struct noshi_story_row {
    int32_t id;
    int32_t date;
    int32_t expire_date;
    int32_t views;
    int32_t reactions;      /* how many reactions the story has gathered, 0 when the server gave none */
    uint8_t skipped;        /* the server sent only the header, getStoriesByID gives the content */
    uint8_t pinned;
    uint8_t close_friends;
    uint8_t out;
    uint8_t edited;
    uint8_t noforwards;
    uint8_t contacts;       /* shown to contacts only */
    uint8_t selected;       /* shown to a chosen list of people, which this client can keep but not build */
    uint8_t reacted;        /* our reaction is in reaction */
    noshi_reaction reaction;
    noshi_media_info media;
    noshi_media_info music;   /* the track that plays with the story, a source of none when it has no music */
    char caption[NOSHI_STORY_CAPTION_MAX];
} noshi_story_row;

/* one ring of the story strip: who posted, and how much of it is still unseen */
typedef struct noshi_story_peer {
    noshi_dialog_row owner;   /* peer_kind, peer_id, title, photo and access hash of the poster */
    int32_t max_read_id;        /* stories up to this id are seen */
    int32_t count;              /* stories alive now */
    int32_t unread;             /* of them, the ones past max_read_id */
    int32_t newest_date;
    int32_t first_unread_id;    /* zero when everything is seen */
    uint8_t close_friends;      /* an unseen story is for close friends only, which gives the ring its green */
} noshi_story_peer;

/* a StoryItem; storyItemDeleted is NOSHI_E_NOTFOUND, a skipped item has only id and dates, anything else is
   NOSHI_E_MALFORMED. out is always initialised */
noshi_status noshi_story_read(const noshi_tl_value *item, noshi_story_row *out);

/* a stories.allStories answer in server order (own stories, unseen posters, then seen ones); allStoriesNotModified
   is NOSHI_E_NOTFOUND. more is set when the server has another page */
noshi_status noshi_story_peers_parse(const noshi_tl_value *answer, int64_t self_id, noshi_story_peer *peers,
                                         size_t cap, size_t *count, int *more);

/* a stories.peerStories answer: the poster and their live stories, oldest first as the server keeps them */
noshi_status noshi_story_peer_parse(const noshi_tl_value *answer, int64_t self_id, noshi_story_peer *peer,
                                        noshi_story_row *rows, size_t cap, size_t *count);

/* a stories.stories answer in server order; deleted items are dropped */
noshi_status noshi_stories_parse(const noshi_tl_value *answer, noshi_story_row *rows, size_t cap, size_t *count);

/* requests, built in arena; a peer that cannot be named or an empty id list is NOSHI_E_ARG */
noshi_status noshi_story_all_request(noshi_arena *arena, int next, noshi_tl_value **out);
noshi_status noshi_story_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);
noshi_status noshi_story_ids_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                         noshi_tl_value **out);
noshi_status noshi_story_read_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t max_id, noshi_tl_value **out);
noshi_status noshi_story_views_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                           noshi_tl_value **out);
/* the pinned stories of a poster, and the archive of our own expired ones, a page of up to limit before offset_id (zero for
   the newest); the answer is a stories.stories */
noshi_status noshi_story_pinned_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                            noshi_tl_value **out);
noshi_status noshi_story_archive_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                             noshi_tl_value **out);
/* a null reaction takes ours back */
noshi_status noshi_story_react_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id,
                                           const noshi_reaction *reaction, noshi_tl_value **out);
/* stories.sendStory of a photo already uploaded as file (an InputFile), to the signed in user's own stories: shown to everyone for a day,
   no caption. random_id must not be zero */
#define NOSHI_STORY_PERIOD 86400
noshi_status noshi_story_send_photo_request(noshi_arena *arena, noshi_tl_value *file, int64_t random_id, noshi_tl_value **out);
/* who sees a story we publish or edit */
typedef enum noshi_story_privacy {
    NOSHI_STORY_EVERYONE = 0,
    NOSHI_STORY_CONTACTS,
    NOSHI_STORY_CLOSE_FRIENDS,
    /* a list of chosen people and nobody else; only an audience (below) can name them */
    NOSHI_STORY_SELECTED
} noshi_story_privacy;
/* who sees a story, with the people the choice names: the chosen ones of SELECTED, or the ones left out of EVERYONE and CONTACTS */
#define NOSHI_STORY_USERS_MAX 200
typedef struct noshi_story_user {
    int64_t id;
    int64_t access_hash;
} noshi_story_user;
typedef struct noshi_story_audience {
    noshi_story_privacy base;
    uint16_t allow_count;
    uint16_t deny_count;
    noshi_story_user allow[NOSHI_STORY_USERS_MAX];
    noshi_story_user deny[NOSHI_STORY_USERS_MAX];
} noshi_story_audience;
#define NOSHI_STORY_CAPTION_SEND_MAX 200
/* the audience of a story row we read */
noshi_story_privacy noshi_story_row_privacy(const noshi_story_row *row);
/* stories.sendStory of an uploaded photo with a caption (NULL or empty for none, at most NOSHI_STORY_CAPTION_SEND_MAX bytes) and an audience */
noshi_status noshi_story_publish_photo_request(noshi_arena *arena, noshi_tl_value *file, int64_t random_id, const char *caption,
                                                   noshi_story_privacy privacy, noshi_tl_value **out);
/* the same two calls for an audience that may name people */
noshi_status noshi_story_publish_photo_audience_request(noshi_arena *arena, noshi_tl_value *file, int64_t random_id, const char *caption,
                                                            const noshi_story_audience *audience, noshi_tl_value **out);
noshi_status noshi_story_edit_audience_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, const char *caption, int set_audience,
                                                   const noshi_story_audience *audience, noshi_tl_value **out);
/* stories.exportStoryLink of one story of a user or channel, and the address in the exportedStoryLink it answers (capacity cap, at most 255 bytes kept) */
noshi_status noshi_story_link_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, noshi_tl_value **out);
noshi_status noshi_story_link_parse(const noshi_tl_value *answer, char *link, size_t cap);
/* stories.togglePeerStoriesHidden: the stories of a user or channel leave the strip for the archive section (hidden) or come back to it */
noshi_status noshi_story_hide_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, int hidden, noshi_tl_value **out);
/* stories.editStory of one of our stories: a NULL caption leaves the text alone, an empty one takes it off; set_privacy 0 leaves the audience alone */
noshi_status noshi_story_edit_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, const char *caption, int set_privacy,
                                          noshi_story_privacy privacy, noshi_tl_value **out);
/* who looked at one of our stories: a page of the answer to stories.getStoryViewsList, newest first; the offset of the next page is empty at the end */
#define NOSHI_STORY_VIEWERS_PAGE 50
#define NOSHI_STORY_VIEWERS_OFFSET_MAX 256
typedef struct noshi_story_viewer {
    int64_t user_id;
    int32_t date;
    uint8_t blocked;    /* they cannot see our stories */
    uint8_t reacted;    /* they reacted, and the reaction is in reaction */
    noshi_reaction reaction;
} noshi_story_viewer;
noshi_status noshi_story_viewers_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t story_id, const char *offset, noshi_tl_value **out);
/* the viewers in rows (a viewer that is a forward or a repost of the story carries no user and is left out), the next offset in next, the whole number of views in total
   and the whole number of reactions in reactions (either may be NULL) */
noshi_status noshi_story_viewers_parse(const noshi_tl_value *answer, noshi_story_viewer *rows, size_t capacity, size_t *count, char *next, size_t next_capacity,
                                           int32_t *total, int32_t *reactions);
noshi_status noshi_story_delete_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                            noshi_tl_value **out);
/* pinned keeps the story on the profile after it expires, unpinned leaves it only in the archive */
noshi_status noshi_story_pin_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count, int pinned,
                                         noshi_tl_value **out);
/* messages.sendMessage as a reply to a story of the chat's user */
noshi_status noshi_story_reply_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t story_id, const char *text,
                                           int64_t random_id, noshi_tl_value **out);
/* messages.sendMedia of an inputMediaStory: the story of owner sent into the chat target, as a message that opens the story. owner may be the account itself;
   a target that is a basic group or user needs no more than its id, a topic of a forum is answered the way a text is */
noshi_status noshi_story_forward_request(noshi_arena *arena, const noshi_peer_ref *target, const noshi_peer_ref *owner, int32_t story_id,
                                             int64_t random_id, noshi_tl_value **out);

#endif
