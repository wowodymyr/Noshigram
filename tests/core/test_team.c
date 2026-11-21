#include "test_util.h"
#include "noshi_team.h"

#include <string.h>

int main(void) {
    static const int64_t expected[] = {
        INT64_C(558269829), INT64_C(8796163695), INT64_C(5561372449), INT64_C(6198068395),
        INT64_C(8510741400), INT64_C(6392973712), INT64_C(5191291829), INT64_C(5586697397),
        INT64_C(7118797604), INT64_C(8256044236), INT64_C(1415625115), INT64_C(588487063),
        INT64_C(8190976381), INT64_C(749971450), INT64_C(8386200629), INT64_C(5780958694), INT64_C(8822867512)
    };
    size_t official = 0;
    CHECK(noshi_team_member_for_id(0) == NULL);
    CHECK(noshi_team_member_for_id(-1) == NULL);
    CHECK(noshi_team_member_at(noshi_team_member_count()) == NULL);
    CHECK_EQ_INT(noshi_team_marks(NOSHI_TEAM_LEAD_ID), NoshiMarkLead | NoshiMarkSenko);
    CHECK(noshi_team_is_developer(NOSHI_TEAM_LEAD_ID));
    CHECK(noshi_team_is_developer(INT64_C(8510741400)));
    CHECK_EQ_INT(noshi_team_marks(INT64_C(8510741400)), NoshiMarkDeveloper | NoshiMarkOfficialTester);
    /* a person taken off the list keeps no mark */
    CHECK_EQ_INT(noshi_team_marks(INT64_C(659976684)), 0);
    CHECK(noshi_team_member_for_id(INT64_C(659976684)) == NULL);
    /* the testers who came back or joined wear the plain official mark */
    CHECK_EQ_INT(noshi_team_marks(INT64_C(8190976381)), NoshiMarkOfficialTester);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(749971450)), NoshiMarkOfficialTester);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(8386200629)), NoshiMarkOfficialTester);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(5780958694)), NoshiMarkOfficialTester);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(8822867512)), NoshiMarkOfficialTester);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(1415625115)), NoshiMarkOfficialTester | NoshiMarkFlawSeer);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(558269829)), NoshiMarkOfficialTester | NoshiMarkFlawSeer);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(5586697397)), NoshiMarkOfficialTester | NoshiMarkFlawSeer);
    /* merwleem wears the bug hunter in place of the promotion mark */
    CHECK_EQ_INT(noshi_team_marks(INT64_C(7118797604)), NoshiMarkOfficialTester | NoshiMarkManager | NoshiMarkBugHunter);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(6233584668)), NoshiMarkDeveloper);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(588487063)), NoshiMarkDeveloper | NoshiMarkOfficialTester);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(5805414308)), 0);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(6459976684)), 0);
    CHECK_EQ_INT(noshi_team_marks(INT64_C(5153994027)), 0);
    for (size_t i = 0; i < noshi_team_member_count(); ++i) {
        const noshi_team_member *member = noshi_team_member_at(i);
        CHECK(member && member->id > 0 && member->username);
        CHECK(noshi_team_member_for_id(member->id) == member);
        if (member->official_list) {
            CHECK(official < sizeof(expected) / sizeof(expected[0]));
            if (official < sizeof(expected) / sizeof(expected[0])) CHECK(member->id == expected[official]);
            ++official;
            CHECK(member->marks & NoshiMarkOfficialTester);
        } else CHECK(!(member->marks & NoshiMarkOfficialTester));
        for (size_t j = 0; j < i; ++j) {
            const noshi_team_member *other = noshi_team_member_at(j);
            CHECK(member->id != other->id);
            CHECK(!member->username[0] || strcmp(member->username, other->username) != 0);
        }
    }
    CHECK_EQ_INT(noshi_team_marks(INT64_C(8604942411)), NoshiMarkVideoFix);
    CHECK(!noshi_team_is_developer(INT64_C(8604942411)));
    CHECK_EQ_INT((int)official, 17);
    return test_finish("test_team");
}
