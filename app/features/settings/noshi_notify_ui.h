#import <UIKit/UIKit.h>

#import "noshi_session_notifysettings.h"
#import "noshi_symbol.h"

/* what the notification screens share: the kinds of the main list, the words for a state and a tone, the tones of the app, and the lists of exceptions */

typedef enum {
    NoshiNotifyKindPrivate,
    NoshiNotifyKindGroups,
    NoshiNotifyKindChannels,
    NoshiNotifyKindStories,
    NoshiNotifyKindReactions,
    /* only the exceptions of every kind, as the alert about a change lists them */
    NoshiNotifyKindAllExceptions
} NoshiNotifyKind;

/* the scope of the account a kind of chat is kept in; not for stories (they ride on private chats) and reactions */
noshi_notify_scope NoshiNotifyScopeOfKind(NoshiNotifyKind kind);

/* "on", "Off", or "Off until Friday" for a mute time say it */
NSString *NoshiNotifyMuteText(int32_t muteUntil);
/* the name of a tone as the settings show it; has says the settings name one at all */
NSString *NoshiNotifySoundText(BOOL has, const noshi_notify_sound *sound);
/* the tones the bundle holds, each as an array of the file name and the title */
NSArray *NoshiNotifyTones(void);
/* a count with its noun, "3 chats" or "2 exceptions"; base is "notif.chats" or "notif.exceptions" */
NSString *NoshiNotifyCountText(NSString *base, NSInteger count);

/* the exceptions that belong in the list of a kind */
NSArray *NoshiNotifyExceptionsForKind(NSArray *all, NoshiNotifyKind kind);

/* a round picture with the initials of a title on a color picked by the id, the size of a row tile */
UIImage *NoshiNotifyInitialsTile(NSString *title, long long seed, CGFloat side);

/* the dates of a mute: now plus an hour, eight hours, two days; forever */
int32_t NoshiNotifyNow(void);
