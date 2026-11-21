#import "noshi_settings_kit.h"
#import "noshi_session.h"

@class NoshiPerson;
@class NoshiStoryAudience;

/* the contacts with a mark each, to choose any number of them; the choice goes to the caller when the page is left by its arrow */
@interface NoshiPeopleSelectController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session title:(NSString *)title chosen:(NSArray *)chosen done:(void (^)(NSArray *people))done;
/* the page in a navigation controller of its own, to be presented over a full screen; the classic theme gets a Close button, which hands the choice over too */
- (UINavigationController *)presentableNavigation;
@end

/* who sees a story, in the words of the app: Everyone, Everyone except, Contacts, Contacts except, Close friends, Selected contacts. the list of people of the
   last three choices is asked for on a page over host. done gets the audience; cancelled runs when nothing was chosen */
void NoshiChooseStoryAudience(UIViewController *host, NoshiSession *session, NoshiStoryAudience *current, void (^done)(NoshiStoryAudience *audience), void (^cancelled)(void));
/* the line that names an audience: "Everyone except 3", "Selected (5)" */
NSString *NoshiStoryAudienceTitle(NoshiStoryAudience *audience);
