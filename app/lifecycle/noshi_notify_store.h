#import <Foundation/Foundation.h>

#include "noshi_notify_prefs.h"

/* the notification settings the phone keeps; the rest are switches of this phone only */

/* posted when anything here changes, on the main thread */
extern NSString *const NoshiNotifyStoreDidChangeNotification;

/* the copy of the settings of a kind of chat; a kind never set has no fields, which means on, shown, default sound */
noshi_peer_notify NoshiNotifyScopeStored(noshi_notify_scope scope);
void NoshiNotifyScopeStore(noshi_notify_scope scope, const noshi_peer_notify *value);

noshi_reaction_notify NoshiNotifyReactionsStored(void);
void NoshiNotifyReactionsStore(const noshi_reaction_notify *value);

/* the rules for a look at the chat list: the account's settings with the switches of the phone */
void NoshiNotifyRulesSnapshot(noshi_notify_rules *out);

/* the switches of the phone */
BOOL NoshiNotifyInAppSounds(void);
void NoshiNotifySetInAppSounds(BOOL on);
BOOL NoshiNotifyInAppVibrate(void);
/* whether a message of this chat shakes the phone while the app is on screen: on unless the person turned it off for the chat; a setting of this phone, since the server keeps no such thing */
BOOL NoshiNotifyChatVibrates(int32_t peerKind, long long peerId);
void NoshiNotifySetChatVibrates(int32_t peerKind, long long peerId, BOOL on);
void NoshiNotifySetInAppVibrate(BOOL on);
BOOL NoshiNotifyInAppPreview(void);
void NoshiNotifySetInAppPreview(BOOL on);
/* a short sound for a message that comes into the chat on screen, and for one sent from it; off by default */
BOOL NoshiNotifyInChatSounds(void);
void NoshiNotifySetInChatSounds(BOOL on);
BOOL NoshiNotifyContactJoined(void);
void NoshiNotifySetContactJoined(BOOL on);
BOOL NoshiNotifyPinnedMessages(void);
void NoshiNotifySetPinnedMessages(BOOL on);
/* the number on the icon: shown at all, counting muted chats too, and counting messages and not chats */
BOOL NoshiNotifyBadgeShown(void);
void NoshiNotifySetBadgeShown(BOOL on);
BOOL NoshiNotifyBadgeMuted(void);
void NoshiNotifySetBadgeMuted(BOOL on);
BOOL NoshiNotifyBadgeMessages(void);
void NoshiNotifySetBadgeMessages(BOOL on);
/* minutes between the reminders of unread messages, zero for never; an hour by default */
NSInteger NoshiNotifyRepeatMinutes(void);
void NoshiNotifySetRepeatMinutes(NSInteger minutes);
/* how the phone shakes for an incoming call: 0 default, 1 short, 2 off, 3 long */
NSInteger NoshiNotifyCallVibration(void);
void NoshiNotifySetCallVibration(NSInteger style);

/* forget the copy of the account's settings and every switch: the state of a new install (the phone's own master switch and power saver stay) */
void NoshiNotifyStoreReset(void);
