#import "noshi_name_badge.h"

#import "noshi_custom_emoji.h"
#import "noshi_developers.h"
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
    return NoshiNameWithBadges(name, document, NO, entities);
}

NSString *NoshiNameWithBadges(NSString *name, long long document, NSUInteger marks, NSArray **entities) {
    if (entities) *entities = nil;
    if ((!document && !marks) || !name.length) return name;
    NSMutableString *text = [NSMutableString stringWithString:name];
    NSMutableArray *list = [NSMutableArray array];
    long long documents[11] = {document, marks & NoshiMarkDeveloper ? NOSHI_DEVELOPER_DOCUMENT : 0, marks & NoshiMarkLead ? NOSHI_LEAD_DOCUMENT : 0,
                              marks & NoshiMarkSenko ? NOSHI_SENKO_DOCUMENT : 0, marks & NoshiMarkTester ? NOSHI_TESTER_DOCUMENT : 0,
                              marks & NoshiMarkPromotion ? NOSHI_PROMOTION_DOCUMENT : 0,
                              marks & NoshiMarkBugHunter ? NOSHI_BUG_HUNTER_DOCUMENT : 0, marks & NoshiMarkOfficialTester ? NOSHI_OFFICIAL_TESTER_DOCUMENT : 0,
                               marks & NoshiMarkManager ? NOSHI_MANAGER_DOCUMENT : 0, marks & NoshiMarkVideoFix ? NOSHI_VIDEO_FIX_DOCUMENT : 0, marks & NoshiMarkFlawSeer ? NOSHI_FLAW_SEER_DOCUMENT : 0};
    for (int i = 0; i < 11; ++i) {
        if (!documents[i]) continue;
        [text appendString:@" "];
        NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji
            range:NSMakeRange(text.length, NoshiBadgePlaceholder.length) url:nil] autorelease];
        entity.documentId = documents[i];
        [list addObject:entity];
        [text appendString:NoshiBadgePlaceholder];
    }
    if (entities) *entities = list;
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
    NSUInteger marks = NoshiMarksOfId(userId);
    NSArray *entities = nil;
    label.dropsUndrawable = YES;
    label.text = NoshiNameWithBadges(name, 0, marks, &entities);
    label.entities = entities;
    if (!session || userId <= 0 || !name.length) return;
    NSString *shown = [[name copy] autorelease];
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:label];
    [session loadStoredPersonOfUserId:userId completion:^(NoshiPerson *person) {
        NoshiEmojiLabel *target = weak.target;
        /* the label may be showing another name by now, as the cells of a list are used again */
        if (!target || !person || ![target.text hasPrefix:shown]) return;
        long long document = NoshiPersonBadgeDocument(person);
        NSUInteger known = marks | NoshiPersonIsDeveloper(person);
        if (!document && known == marks) return;
        NSArray *more = nil;
        target.text = NoshiNameWithBadges(shown, document, known, &more);
        target.entities = more;
        if (person.emojiStatus) {
            NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:person.emojiStatus]], session, media, ^{
                [(NoshiEmojiLabel *)weak.target setNeedsDisplay];
            });
        }
    }];
}
