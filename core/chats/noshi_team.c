#include "noshi_team.h"

#define DEV NoshiMarkDeveloper
#define OFF NoshiMarkOfficialTester
#define PROMO NoshiMarkPromotion
#define MANAGER NoshiMarkManager
#define VIDEOFIX NoshiMarkVideoFix
#define SEER NoshiMarkFlawSeer

static const noshi_team_member members[] = {
    {INT64_C(558269829), "kfrom7", OFF | SEER, 1},
    {INT64_C(8796163695), "anazerka", DEV | OFF, 1},
    {INT64_C(5561372449), "CookieValerka", OFF, 1},
    {INT64_C(6198068395), "inraxx", OFF, 1},
    {INT64_C(8510741400), "LimeDev", DEV | OFF, 1},
    {INT64_C(6392973712), "Lineysom", OFF, 1},
    {INT64_C(5191291829), "loveiOS6", DEV | OFF, 1},
    {INT64_C(5586697397), "xaxaxaxaxxaxaxaxaxaxaxaxaxaxa", OFF | SEER, 1},
    {INT64_C(7118797604), "merwleem", OFF | MANAGER | NoshiMarkBugHunter, 1},
    {INT64_C(8256044236), "s3dativee", OFF, 1},
    {INT64_C(1415625115), "not_a_modder", OFF | SEER, 1},
    {INT64_C(6233584668), "svcayon4ik", DEV, 0},
    {NOSHI_TEAM_LEAD_ID, "sqmrak", NoshiMarkLead | NoshiMarkSenko, 0},
    {INT64_C(5435278149), "QWERTYU1OPZ", DEV, 0},
    {INT64_C(588487063), "menstry", DEV | OFF, 1},
    {INT64_C(8190976381), "fly1ngangel", OFF, 1},
    {INT64_C(749971450), "shizotoaster", OFF, 1},
    {INT64_C(8386200629), "Siqvw", OFF, 1},
    {INT64_C(5780958694), "appIebionic", OFF, 1},
    {INT64_C(8822867512), "rakamaqfo", OFF, 1},
    {INT64_C(5390055485), "nestorvashenko", DEV, 0},
    {INT64_C(940506028), "Maks_097", NoshiMarkTester, 0},
    {INT64_C(7801631734), "QuaIcomm", NoshiMarkTester, 0},
    {INT64_C(7752146730), "nowme77", NoshiMarkTester, 0},
    {INT64_C(7073807722), "Radickdz", PROMO, 0},
    {INT64_C(5850832376), "Xmas_UnrealKot", PROMO, 0},
    {INT64_C(5921838671), "jestik22", PROMO, 0},
    /* the author of NoshiVideoFix, whose way of playing fragmented mp4 is in the app now; the username is not known, so the hint is empty */
    {INT64_C(8604942411), "", VIDEOFIX, 0}
};

size_t noshi_team_member_count(void) { return sizeof(members) / sizeof(members[0]); }
const noshi_team_member *noshi_team_member_at(size_t index) {
    return index < noshi_team_member_count() ? &members[index] : NULL;
}
const noshi_team_member *noshi_team_member_for_id(int64_t id) {
    for (size_t i = 0; i < noshi_team_member_count(); ++i) if (members[i].id == id) return &members[i];
    return NULL;
}
uint32_t noshi_team_marks(int64_t id) {
    const noshi_team_member *member = noshi_team_member_for_id(id);
    return member ? member->marks : 0;
}
int noshi_team_is_developer(int64_t id) {
    return (noshi_team_marks(id) & (NoshiMarkDeveloper | NoshiMarkLead)) != 0;
}
