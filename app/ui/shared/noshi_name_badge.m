#import "noshi_name_badge.h"

#import "noshi_custom_emoji.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_message.h"
#import "noshi_person.h"
#import "noshi_session_bots.h"
#import "noshi_weak_reference.h"
#include "noshi_people.h"

/* a text symbol, not an emoji: the layout replaces it with the badge, and it draws nothing of its own while a status picture loads */
static NSString *const NoshiBadgePlaceholder = @"★";

long long NoshiBadgeDocument(long long emojiStatus, BOOL premium) {
    if (emojiStatus > 0) return emojiStatus;
    return premium ? NOSHI_PREMIUM_STAR_DOCUMENT : 0;
}

long long NoshiDialogBadgeDocument(NoshiDialog *dialog) {
    if (dialog.peerKind == 1 && dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID) return NOSHI_TELEGRAM_VERIFIED_DOCUMENT;
    return dialog.saved ? 0 : NoshiBadgeDocument(dialog.emojiStatus, dialog.premium);
}

long long NoshiPersonBadgeDocument(NoshiPerson *person) {
    if (person.userId == NOSHI_TELEGRAM_SERVICE_USER_ID) return NOSHI_TELEGRAM_VERIFIED_DOCUMENT;
    return NoshiBadgeDocument(person.emojiStatus, person.premium);
}

NSString *NoshiNameWithBadge(NSString *name, long long document, NSArray **entities) {
    if (entities) *entities = nil;
    if (!document || !name.length) return name;
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@ ", name];
    NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji
        range:NSMakeRange(text.length, NoshiBadgePlaceholder.length) url:nil] autorelease];
    entity.documentId = document;
    [text appendString:NoshiBadgePlaceholder];
    if (entities) *entities = [NSArray arrayWithObject:entity];
    return text;
}

void NoshiLoadBadgePictures(NSArray *documents, NoshiSession *session, NoshiMediaCache *media, void (^redraw)(void)) {
    NSMutableArray *wanted = [NSMutableArray array];
    for (NSNumber *document in documents) {
        if (document.longLongValue > 0 && ![wanted containsObject:document]) [wanted addObject:document];
    }
    if (!wanted.count || !session || !media) return;
    [NoshiCustomEmojiLoader loadDocuments:wanted session:session media:media documents:nil picture:redraw];
}

static void NoshiRedrawTreeOfView(UIView *view) {
    [view setNeedsDisplay];
    for (UIView *child in view.subviews) NoshiRedrawTreeOfView(child);
}

void NoshiRedrawVisibleRows(UITableView *table) {
    for (UITableViewCell *cell in table.visibleCells) NoshiRedrawTreeOfView(cell.contentView);
}

void NoshiShowNameWithBadges(NoshiEmojiLabel *label, NSString *name, long long userId, NoshiSession *session, NoshiMediaCache *media) {
    label.dropsUndrawable = YES;
    label.text = name;
    label.entities = nil;
    if (!session || userId <= 0 || !name.length) return;
    NSString *shown = [[name copy] autorelease];
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:label];
    [session loadStoredPersonOfUserId:userId completion:^(NoshiPerson *person) {
        NoshiEmojiLabel *target = weak.target;
        /* the label may be showing another name by now, as the cells of a list are used again */
        if (!target || !person || ![target.text hasPrefix:shown]) return;
        long long document = NoshiPersonBadgeDocument(person);
        if (!document) return;
        NSArray *more = nil;
        target.text = NoshiNameWithBadge(shown, document, &more);
        target.entities = more;
        if (person.emojiStatus) {
            NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:person.emojiStatus]], session, media, ^{
                [(NoshiEmojiLabel *)weak.target setNeedsDisplay];
            });
        }
    }];
}
