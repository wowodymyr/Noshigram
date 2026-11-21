#import "noshi_custom_gift.h"

#import "noshi_developers.h"
#import "noshi_person.h"
#import "noshi_session_bots.h"

#include <string.h>

/* the gifts, in the order of their numbers */
typedef struct {
    int64_t owner;
    int32_t number;
    int64_t giftId;
    const char *title;
    const char *model;
    const char *symbol;
    const char *backdrop;
    uint32_t center, edge, text, pattern;
    int32_t date;
    const char *note;
    const char *image;
} NoshiCustomGiftSpec;

static const NoshiCustomGiftSpec NoshiCustomGiftSpecs[] = {
    /* #001: a plush Senko from the lead developer, on warm amber */
    {NOSHI_TEAM_LEAD_ID, 1, -1, "Senko", "Plush Senko", "Soft Shapes", "Amber Glow", 0xFFB74D, 0xE65100, 0xFFE9C7, 0xFFFFFF, 1793222400, "чееее ахахахахах", "gift_custom_senko"},
    /* #002: the doge meme from the lead developer, on the beige of the picture */
    {NOSHI_TEAM_LEAD_ID, 2, -2, "eblan", "Doge", "Soft Shapes", "Beige", 0xC6AA6B, 0x7E5641, 0xFFF3D6, 0xFFFFFF, 1793222400, "еблан", "gift_custom_eblan"},
    /* #003: a plush Pusheen from the lead developer to merwleem, on warm taupe */
    {INT64_C(7118797604), 3, -3, "Pusheen", "Plush Pusheen", "Soft Shapes", "Taupe", 0xC9B3A1, 0x7A5C4A, 0xFFF1E4, 0xFFFFFF, 1793222400, "pusheen :3", "gift_custom_pusheen"}
};
#define CUSTOM_GIFT_COUNT (sizeof(NoshiCustomGiftSpecs) / sizeof(NoshiCustomGiftSpecs[0]))
static NSString *const NoshiCustomGiftSenderUsername = @"sqmrak";

NSString *NoshiCustomGiftNumberText(int32_t number) {
    return [NSString stringWithFormat:@"#%03d", (int)number];
}

/* main thread only */
static NoshiPerson *NoshiCustomGiftSender;
static NSMutableArray *NoshiCustomGiftWaiting;
/* a failed ask is not repeated by every page: the gift then names him without a picture */
static BOOL NoshiCustomGiftAsked;

static BOOL NoshiCustomGiftOwns(const NoshiCustomGiftSpec *spec, NoshiDialog *owner) {
    /* the profile of the account itself is asked through its saved messages, which carry its own user id */
    return owner && owner.peerKind == 1 && owner.peerId == spec->owner;
}

static BOOL NoshiCustomGiftApplies(NoshiDialog *owner) {
    for (size_t i = 0; i < CUSTOM_GIFT_COUNT; ++i) if (NoshiCustomGiftOwns(&NoshiCustomGiftSpecs[i], owner)) return YES;
    return NO;
}

BOOL NoshiCustomGiftNeedsSender(NoshiDialog *owner) {
    return !NoshiCustomGiftSender && !NoshiCustomGiftAsked && NoshiCustomGiftApplies(owner);
}

void NoshiCustomGiftLoadSender(NoshiSession *session, void (^done)(void)) {
    if (NoshiCustomGiftSender || NoshiCustomGiftAsked || !session) {
        done();
        return;
    }
    if (!NoshiCustomGiftWaiting) NoshiCustomGiftWaiting = [[NSMutableArray alloc] init];
    BOOL running = NoshiCustomGiftWaiting.count > 0;
    [NoshiCustomGiftWaiting addObject:[[done copy] autorelease]];
    if (running) return;
    NoshiLoadTeamPerson(session, NOSHI_TEAM_LEAD_ID, ^(NoshiPerson *person, NSString *errorName) {
        NoshiCustomGiftAsked = YES;
        if (person && person.userId > 0) NoshiCustomGiftSender = [person retain];
        else NSLog(@"noshigram: the sender of the custom gift was not resolved: %@", errorName);
        NSArray *waiting = [[NoshiCustomGiftWaiting copy] autorelease];
        [NoshiCustomGiftWaiting removeAllObjects];
        for (void (^waiter)(void) in waiting) waiter();
    });
}

NSArray *NoshiCustomGiftsForDialog(NoshiDialog *owner) {
    if (!NoshiCustomGiftApplies(owner)) return [NSArray array];
    NSMutableArray *gifts = [NSMutableArray arrayWithCapacity:CUSTOM_GIFT_COUNT];
    for (size_t i = 0; i < CUSTOM_GIFT_COUNT; ++i) {
        const NoshiCustomGiftSpec *spec = &NoshiCustomGiftSpecs[i];
        if (!NoshiCustomGiftOwns(spec, owner)) continue;
        noshi_saved_gift row;
        memset(&row, 0, sizeof(row));
        row.gift.id = spec->giftId;
        row.gift.catalog_id = spec->giftId;
        row.gift.unique = 1;
        row.gift.num = spec->number;
        row.gift.has_backdrop = 1;
        row.gift.backdrop_center = spec->center;
        row.gift.backdrop_edge = spec->edge;
        row.gift.backdrop_text = spec->text;
        row.gift.backdrop_pattern = spec->pattern;
        snprintf(row.gift.title, sizeof(row.gift.title), "%s", spec->title);
        snprintf(row.gift.model, sizeof(row.gift.model), "%s", spec->model);
        snprintf(row.gift.pattern, sizeof(row.gift.pattern), "%s", spec->symbol);
        snprintf(row.gift.backdrop, sizeof(row.gift.backdrop), "%s", spec->backdrop);
        /* the sender stays the same account when its username changes */
        row.from_id = NOSHI_TEAM_LEAD_ID;
        snprintf(row.from_name, sizeof(row.from_name), "%s", NoshiCustomGiftSenderUsername.UTF8String);
        snprintf(row.note, sizeof(row.note), "%s", spec->note);
        row.date = spec->date;
        /* they stand first on the profile, as pinned gifts do, and wear the pin */
        row.pinned = 1;
        NoshiSavedGift *gift = [NoshiSavedGift savedGiftWithRow:&row];
        gift.customImageName = [NSString stringWithUTF8String:spec->image];
        [gift setSenderPerson:NoshiCustomGiftSender];
        [gifts addObject:gift];
    }
    return gifts;
}
