#import <UIKit/UIKit.h>

#import "noshi_session.h"

/* the people who took part in the development of Noshigram, the ones of the credits in About */

#include "noshi_team.h"
@class NoshiPerson;

BOOL NoshiIsDeveloperId(long long userId);
NSUInteger NoshiMarksOfId(long long userId);
/* the marks a developer gave himself on this phone: they take the place of the real ones of that account wherever its name is drawn, and nothing leaves the phone. The bits are the NoshiMark values */
BOOL NoshiHasLocalMarks(long long userId);
NSUInteger NoshiLocalMarks(long long userId);
void NoshiSetLocalMarks(long long userId, NSUInteger marks);
void NoshiClearLocalMarks(long long userId);
/* posted on the main thread when the marks of an account were set or cleared, so lists draw their names again */
extern NSString *const NoshiLocalMarksDidChangeNotification;
NSArray *NoshiOfficialTesterIds(void);
NSString *NoshiTeamUsername(long long userId);
extern NSString *const NoshiOpenTeamPersonNotification;
/* resolves a known id with this account's access hash; the username hint is accepted only when it still names that id */
void NoshiLoadTeamPerson(NoshiSession *session, long long userId, void (^completion)(NoshiPerson *person, NSString *errorName));
/* a chat row or a chat header: a private chat or a bot chat with one of them; zero when the person wears nothing */
NSUInteger NoshiDialogIsDeveloper(NoshiDialog *dialog);
NSUInteger NoshiPersonIsDeveloper(NoshiPerson *person);
NSUInteger NoshiMarkForDocument(long long document);

/* the plate that says why a mark is there, over whatever screen is up */
void NoshiShowMarkNotice(NSString *name, NSUInteger mark);
/* the same for a mark of a known account, whose plate may carry a line of its own (developer.flaw_seer.notice.<id> in the strings) */
void NoshiShowMarkNoticeForUser(NSString *name, NSUInteger mark, long long userId);
