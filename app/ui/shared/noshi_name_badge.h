#import <UIKit/UIKit.h>

#import "noshi_emoji_label.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"

/* the mark after the name of a Telegram Premium user: the custom emoji they chose as a status, or the Premium star
   when they chose none */

/* the document to draw after a name: the live status, else the Premium star for a Premium user, else zero */
long long NoshiBadgeDocument(long long emojiStatus, BOOL premium);
long long NoshiDialogBadgeDocument(NoshiDialog *dialog);
long long NoshiPersonBadgeDocument(NoshiPerson *person);

/* the name followed by the badge, with the entity list that draws it in entities; the name unchanged and nil entities for document zero */
NSString *NoshiNameWithBadge(NSString *name, long long document, NSArray **entities);

/* the same with the hammer of the developers after the status badge, for a person who took part in the development of Noshigram; developer NO is the call above */
NSString *NoshiNameWithBadges(NSString *name, long long document, NSUInteger marks, NSArray **entities);

/* fetches the pictures of the statuses among documents (NSNumbers; the star and zero are skipped); redraw runs on
   the main thread each time one lands */
/* draws the rows on screen again, for a picture that landed after they were laid out; it changes no size */
void NoshiRedrawVisibleRows(UITableView *table);

void NoshiLoadBadgePictures(NSArray *documents, NoshiSession *session, NoshiMediaCache *media, void (^redraw)(void));

/* sets a label to the name of a person with the marks of Noshigram after it at once, and, when the account has a copy of the person (asked for by user id, which a
   screen that only knows a name and an id, such as a call, has), with the emoji status or the Premium star too, which come a moment later. the label is made
   to draw as the names of the app are, emoji as pictures and no boxes; session and media may be nil, then only the marks show */
void NoshiShowNameWithBadges(NoshiEmojiLabel *label, NSString *name, long long userId, NoshiSession *session, NoshiMediaCache *media);
