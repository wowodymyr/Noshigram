#import "noshi_developers.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_emoji_label.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_dialog.h"
#import "noshi_person.h"
#import "noshi_session_bots.h"
#import "noshi_session_profile.h"
#import "noshi_custom_emoji.h"

/* the class methods stand in for a target the plate's gestures and its timer can reach without holding anything */
@interface NoshiDeveloperPlateTarget : NSObject
+ (void)hide;
+ (void)tapped:(UITapGestureRecognizer *)tap;
@end

NSString *const NoshiOpenTeamPersonNotification = @"NoshiOpenTeamPerson";

void NoshiLoadTeamPerson(NoshiSession *session, long long userId, void (^completion)(NoshiPerson *, NSString *)) {
    NSString *hint = NoshiTeamUsername(userId);
    if (!session || !hint || !completion) {
        if (completion) completion(nil, @"USER_ID_INVALID");
        return;
    }
    [session loadStoredPersonOfUserId:userId completion:^(NoshiPerson *held) {
        NoshiDialog *dialog = held ? [NoshiDialog dialogWithPerson:held] : nil;
        if (dialog) {
            [session loadFullUserOfDialog:dialog completion:^(NoshiFullUser *full, NSString *error) {
                if (full.person && full.person.userId == userId) completion(full.person, nil);
                else {
                    NSLog(@"noshigram: team user %lld could not be refreshed: %@", userId, error ? error : @"unexpected user");
                    completion(held, nil);
                }
            }];
        } else {
            [session resolveUsername:hint completion:^(NoshiDialog *resolved, NoshiPerson *person, NSString *error) {
                (void)resolved;
                if (person.userId == userId) completion(person, nil);
                else completion(nil, error ? error : @"USER_ID_INVALID");
            }];
        }
    }];
}

BOOL NoshiIsDeveloperId(long long userId) { return noshi_team_is_developer(userId) != 0; }
NSString *const NoshiLocalMarksDidChangeNotification = @"NoshiLocalMarksDidChange";
static NSString *const NoshiLocalMarksKey = @"noshigram.developer.localmarks";

static NSString *NoshiLocalMarksName(long long userId) { return [NSString stringWithFormat:@"%lld", userId]; }

BOOL NoshiHasLocalMarks(long long userId) {
    return userId > 0 && [[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiLocalMarksKey] objectForKey:NoshiLocalMarksName(userId)] != nil;
}

NSUInteger NoshiLocalMarks(long long userId) {
    return (NSUInteger)[[[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiLocalMarksKey] objectForKey:NoshiLocalMarksName(userId)] unsignedIntegerValue];
}

void NoshiSetLocalMarks(long long userId, NSUInteger marks) {
    if (userId <= 0) return;
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiLocalMarksKey]];
    [all setObject:[NSNumber numberWithUnsignedInteger:marks] forKey:NoshiLocalMarksName(userId)];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:NoshiLocalMarksKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiLocalMarksDidChangeNotification object:nil];
}

void NoshiClearLocalMarks(long long userId) {
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiLocalMarksKey]];
    [all removeObjectForKey:NoshiLocalMarksName(userId)];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:NoshiLocalMarksKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiLocalMarksDidChangeNotification object:nil];
}

NSUInteger NoshiMarksOfId(long long userId) {
    return NoshiHasLocalMarks(userId) ? NoshiLocalMarks(userId) : noshi_team_marks(userId);
}
NSString *NoshiTeamUsername(long long userId) {
    const noshi_team_member *member = noshi_team_member_for_id(userId);
    return member ? [NSString stringWithUTF8String:member->username] : nil;
}
NSArray *NoshiOfficialTesterIds(void) {
    NSMutableArray *ids = [NSMutableArray array];
    for (size_t i = 0; i < noshi_team_member_count(); ++i) {
        const noshi_team_member *member = noshi_team_member_at(i);
        if (member->official_list) [ids addObject:[NSNumber numberWithLongLong:member->id]];
    }
    return ids;
}
NSUInteger NoshiDialogIsDeveloper(NoshiDialog *dialog) {
    return dialog && dialog.peerKind == 1 && !dialog.saved ? NoshiMarksOfId(dialog.peerId) : 0;
}
NSUInteger NoshiPersonIsDeveloper(NoshiPerson *person) {
    return person ? NoshiMarksOfId(person.userId) : 0;
}

NSUInteger NoshiMarkForDocument(long long document) {
    if (document == NOSHI_FLAW_SEER_DOCUMENT) return NoshiMarkFlawSeer;
    if (document == NOSHI_MANAGER_DOCUMENT) return NoshiMarkManager;
    if (document == NOSHI_VIDEO_FIX_DOCUMENT) return NoshiMarkVideoFix;
    if (document == NOSHI_PROMOTION_DOCUMENT) return NoshiMarkPromotion;
    if (document == NOSHI_BUG_HUNTER_DOCUMENT) return NoshiMarkBugHunter;
    if (document == NOSHI_DEVELOPER_DOCUMENT) return NoshiMarkDeveloper;
    if (document == NOSHI_LEAD_DOCUMENT) return NoshiMarkLead;
    if (document == NOSHI_SENKO_DOCUMENT) return NoshiMarkSenko;
    if (document == NOSHI_TESTER_DOCUMENT) return NoshiMarkTester;
    if (document == NOSHI_OFFICIAL_TESTER_DOCUMENT) return NoshiMarkOfficialTester;
    return 0;
}

/* the plate is a view of the app, not a system alert: the name on it is drawn by the label that knows odd nicks and emoji, and it comes up at once */
#define PLATE_SECONDS 3.2
#define PLATE_SIDE 52.0

static UIView *NoshiPlate;

static void NoshiHidePlate(UIView *plate) {
    if (NoshiPlate != plate) return;
    NoshiPlate = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:[NoshiDeveloperPlateTarget class]];
    NoshiCacheForMotion(plate);
    [UIView animateWithDuration:0.18 animations:^{
        plate.alpha = 0;
        plate.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(BOOL finished) {
        (void)finished;
        [plate removeFromSuperview];
        [plate release];
    }];
}

@implementation NoshiDeveloperPlateTarget
+ (void)hide { if (NoshiPlate) NoshiHidePlate(NoshiPlate); }
+ (void)tapped:(UITapGestureRecognizer *)tap { if (tap.view == NoshiPlate) NoshiHidePlate(NoshiPlate); }
@end

/* the line under the nickname of a flaw seer: the account may have one of its own in the strings, and the rest share the common one */
static NSString *NoshiFlawSeerNotice(long long userId) {
    if (userId > 0) {
        NSString *key = [NSString stringWithFormat:@"developer.flaw_seer.notice.%lld", userId];
        NSString *own = [[NSBundle mainBundle] localizedStringForKey:key value:@"" table:nil];
        if (own.length && ![own isEqualToString:key]) return own;
    }
    return NSLocalizedString(@"developer.flaw_seer.notice", nil);
}

void NoshiShowMarkNotice(NSString *name, NSUInteger mark) {
    NoshiShowMarkNoticeForUser(name, mark, 0);
}

void NoshiShowMarkNoticeForUser(NSString *name, NSUInteger mark, long long userId) {
    UIView *window = NoshiOverlayHost();
    if (!window) return;
    if (NoshiPlate) {
        UIView *old = NoshiPlate;
        NoshiPlate = nil;
        [old removeFromSuperview];
        [old release];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:[NoshiDeveloperPlateTarget class]];
    CGFloat width = MIN(window.bounds.size.width - 32, 360);
    CGFloat textX = 16 + PLATE_SIDE + 12;
    CGFloat textWidth = MAX(1, width - textX - 16);
    UIView *plate = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 84)];
    plate.backgroundColor = NoshiColorCard();
    plate.layer.cornerRadius = 20;
    plate.layer.shadowColor = [UIColor blackColor].CGColor;
    plate.layer.shadowOpacity = 0.28f;
    plate.layer.shadowRadius = 14;
    plate.layer.shadowOffset = CGSizeMake(0, 4);
    UIImage *badge = mark == NoshiMarkFlawSeer ? [NoshiCustomEmoji imageForDocument:NOSHI_FLAW_SEER_DOCUMENT] : mark == NoshiMarkVideoFix ? [NoshiCustomEmoji imageForDocument:NOSHI_VIDEO_FIX_DOCUMENT] : mark == NoshiMarkManager ? [NoshiCustomEmoji imageForDocument:NOSHI_MANAGER_DOCUMENT] : mark == NoshiMarkOfficialTester ? [NoshiCustomEmoji imageForDocument:NOSHI_OFFICIAL_TESTER_DOCUMENT] : mark == NoshiMarkBugHunter ? [NoshiCustomEmoji imageForDocument:NOSHI_BUG_HUNTER_DOCUMENT] : mark == NoshiMarkPromotion ? [NoshiCustomEmoji imageForDocument:NOSHI_PROMOTION_DOCUMENT] :
        [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:mark == NoshiMarkTester ? @"badge_tester" : (mark == NoshiMarkSenko ? @"badge_senko" : (mark == NoshiMarkLead ? @"badge_lead" : @"badge_developer")) ofType:@"png"]];
    UIImageView *hammer = [[[UIImageView alloc] initWithImage:badge] autorelease];
    hammer.contentMode = UIViewContentModeScaleAspectFit;
    [plate addSubview:hammer];
    NoshiEmojiLabel *who = [[[NoshiEmojiLabel alloc] init] autorelease];
    who.font = NoshiFontSemibold(17);
    who.textColor = NoshiColorTitle();
    who.dropsUndrawable = YES;
    /* the elite testers wear their own nickname on the plate */
    who.text = name.length ? name : NSLocalizedString(@"developer.someone", nil);
    who.frame = CGRectMake(textX, 17, textWidth, 22);
    [plate addSubview:who];
    UILabel *what = [[[UILabel alloc] init] autorelease];
    what.backgroundColor = [UIColor clearColor];
    what.font = NoshiFontRegular(14);
    what.textColor = NoshiColorSecondary();
    what.numberOfLines = 0;
    what.lineBreakMode = UILineBreakModeWordWrap;
    what.text = mark == NoshiMarkFlawSeer ? NoshiFlawSeerNotice(userId) : NSLocalizedString(mark == NoshiMarkVideoFix ? @"developer.videofix" : mark == NoshiMarkManager ? @"developer.manager" : mark == NoshiMarkOfficialTester ? @"developer.official_tester" : mark == NoshiMarkBugHunter ? @"developer.bug_hunter.notice" : (mark == NoshiMarkPromotion ? @"developer.promotion" : (mark == NoshiMarkTester ? @"developer.tester" : (mark == NoshiMarkSenko ? @"developer.senko" : (mark == NoshiMarkLead ? @"developer.lead" : @"developer.notice")))), nil);
    CGFloat textHeight = MAX(34, ceil([what sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height));
    CGFloat height = MAX(84, 41 + textHeight + 9);
    what.frame = CGRectMake(textX, 41, textWidth, textHeight);
    [plate addSubview:what];
    plate.bounds = CGRectMake(0, 0, width, height);
    NoshiSetShadowPath(plate, 20);
    hammer.frame = CGRectMake(16, (height - PLATE_SIDE) / 2, PLATE_SIDE, PLATE_SIDE);
    CGFloat top = NoshiStatusBarHeight() + 10;
    plate.center = CGPointMake(CGRectGetMidX(window.bounds), top + height / 2);
    plate.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [plate addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:[NoshiDeveloperPlateTarget class] action:@selector(tapped:)] autorelease]];
    [window addSubview:plate];
    NoshiPlate = plate;
    plate.alpha = 0;
    plate.transform = CGAffineTransformMakeTranslation(0, -24);
    NoshiCacheForMotion(plate);
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        plate.alpha = 1;
        plate.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        (void)finished;
        if (NoshiPlate == plate) NoshiUncacheAfterMotion(plate);
    }];
    [[NoshiDeveloperPlateTarget class] performSelector:@selector(hide) withObject:nil afterDelay:PLATE_SECONDS];
}
