#ifndef NOSHI_TEAM_H
#define NOSHI_TEAM_H

#include <stddef.h>
#include <stdint.h>

enum {
    NoshiMarkDeveloper = 1,
    NoshiMarkSenko = 2,
    NoshiMarkTester = 4,
    NoshiMarkLead = 8,
    NoshiMarkPromotion = 32,
    NoshiMarkBugHunter = 64,
    NoshiMarkOfficialTester = 128,
    NoshiMarkManager = 256,
    NoshiMarkVideoFix = 512,
    /* "this person sees flaws in everything": the elite testers who wear their own nickname on the plate */
    NoshiMarkFlawSeer = 1024
};

#define NOSHI_TEAM_LEAD_ID INT64_C(8202789099)

/* names are lookup hints; identity and marks belong to the numeric account id */
typedef struct noshi_team_member {
    int64_t id;
    const char *username;
    uint32_t marks;
    int official_list;
} noshi_team_member;

const noshi_team_member *noshi_team_member_for_id(int64_t id);
size_t noshi_team_member_count(void);
const noshi_team_member *noshi_team_member_at(size_t index);
uint32_t noshi_team_marks(int64_t id);
int noshi_team_is_developer(int64_t id);

#endif
