#ifndef NOSHI_POLL_H
#define NOSHI_POLL_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_tl.h"

/* the server allows ten answers; a few more are kept in case a newer layer raises that */
#define NOSHI_POLL_ANSWERS_MAX 12
#define NOSHI_POLL_QUESTION_MAX 400
#define NOSHI_POLL_ANSWER_MAX 200
/* the token that names an answer is at most this long (the server keeps to one byte, the schema allows a hundred) */
#define NOSHI_POLL_OPTION_MAX 100
/* the server names the last few who voted of a public poll, and the clients show three of them */
#define NOSHI_POLL_RECENT_MAX 3

/* the custom emoji and styles of a question or an answer; links are left out, since a poll has no room for their addresses */
#define NOSHI_POLL_ENTITIES_MAX 12
typedef struct noshi_poll_entity {
    uint8_t kind;           /* noshi_entity_kind */
    uint8_t flags;
    int32_t offset;         /* UTF-16 units into the text */
    int32_t length;
    int64_t document_id;    /* custom emoji only */
} noshi_poll_entity;

typedef struct noshi_poll_answer {
    char text[NOSHI_POLL_ANSWER_MAX];
    uint8_t entity_count;
    noshi_poll_entity entities[NOSHI_POLL_ENTITIES_MAX];
    uint8_t option[NOSHI_POLL_OPTION_MAX];
    uint8_t option_len;
    int32_t voters;         /* zero when the server did not count them for this account */
    uint8_t chosen;         /* this account voted for it */
    uint8_t correct;        /* the right answer of a quiz, told once the account answered or the quiz is over */
} noshi_poll_answer;

typedef struct noshi_poll {
    int64_t id;
    uint8_t present;        /* the message carries a poll */
    uint8_t closed;
    uint8_t public_voters;  /* the voters can be seen; otherwise the poll is anonymous */
    uint8_t multiple;       /* several answers can be picked */
    uint8_t quiz;           /* one answer is right */
    uint8_t revoting_disabled;  /* an answer cannot be taken back */
    uint8_t hide_results;   /* the counts stay hidden until the poll is closed */
    uint8_t has_counts;     /* the server told how many voted for the answers (not just that this account did) */
    int32_t total_voters;
    uint8_t answer_count;
    uint8_t recent_voter_count;
    int64_t recent_voters[NOSHI_POLL_RECENT_MAX];  /* user ids, the newest first; a voter that is not a user is left out */
    char question[NOSHI_POLL_QUESTION_MAX];
    uint8_t question_entity_count;
    noshi_poll_entity question_entities[NOSHI_POLL_ENTITIES_MAX];
    noshi_poll_answer answers[NOSHI_POLL_ANSWERS_MAX];
} noshi_poll;

/* reads a messageMediaPoll; returns 1 and fills out; 0 with out cleared for anything else, a poll without a
   question or without a usable answer */
int noshi_poll_read(const noshi_tl_value *media, noshi_poll *out);

struct noshi_peer_ref;

typedef struct noshi_poll_choice {
    uint8_t option[NOSHI_POLL_OPTION_MAX];
    size_t option_len;
} noshi_poll_choice;

/* messages.sendVote. count is zero to take the vote back, and at most NOSHI_POLL_ANSWERS_MAX; a token that is empty or too long, or a
   message id that is not positive, is NOSHI_E_ARG */
noshi_status noshi_poll_vote_request(noshi_arena *arena, const struct noshi_peer_ref *peer, int32_t message_id, const noshi_poll_choice *choices,
                                         size_t count, noshi_tl_value **out);

#endif
