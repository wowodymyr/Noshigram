#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include "noshi_tab_order.h"

/* the chat settings of the signed in person, from the Chat Settings screen (ThemeActivity) */
extern NSString *const NoshiChatSettingsDidChangeNotification;
/* TRACE: temporary */
void NoshiChatTrace(NSString *line);

/* the message text size in points, 12 to 30; the default is 16 (18 on an iPad) */
#define NOSHI_CHAT_TEXT_SIZE_MIN 12
#define NOSHI_CHAT_TEXT_SIZE_MAX 30
NSInteger NoshiChatTextSize(void);
void NoshiChatSetTextSize(NSInteger size);
NSInteger NoshiChatDefaultTextSize(void);

/* the corner radius of a message bubble, 0 to 17; the default is 17 */
#define NOSHI_CHAT_BUBBLE_RADIUS_MIN 0
#define NOSHI_CHAT_BUBBLE_RADIUS_MAX 17
NSInteger NoshiChatBubbleRadius(void);
void NoshiChatSetBubbleRadius(NSInteger radius);
/* the same setting for the classic bubble, whose corners are 15 points where the modern ones are 17; the slider
   scaled to the classic range, so the default of both is the shape each style had before the setting existed */
NSInteger NoshiChatClassicBubbleRadius(void);

typedef enum {
    /* a row of the chat list is the name and one line of the last message */
    NoshiChatListTwoLines = 0,
    /* a row gives the last message a second line when it needs it */
    NoshiChatListThreeLines
} NoshiChatListStyle;
/* the default is the three line row, which is what the list drew before the setting existed */
NoshiChatListStyle NoshiChatListStyleStored(void);
void NoshiChatSetListStyle(NoshiChatListStyle style);

/* enter sends the message instead of starting a new line; the default is off */
BOOL NoshiChatSendByEnter(void);
void NoshiChatSetSendByEnter(BOOL on);

/* the media and sound switches of the screen, with the defaults (SharedConfig) except where the app already
   behaved one way */
/* a tap near the left or right edge of the media viewer moves to the previous or next picture instead of hiding the bars; default on */
BOOL NoshiChatNextMediaTap(void);
void NoshiChatSetNextMediaTap(BOOL on);
/* a voice message plays from the earpiece while the phone is held to the ear; default on */
BOOL NoshiChatRaiseToListen(void);
void NoshiChatSetRaiseToListen(BOOL on);
/* holding the phone to the ear in a chat records a voice message, and lowering it sends it; default off */
BOOL NoshiChatRaiseToSpeak(void);
void NoshiChatSetRaiseToSpeak(BOOL on);
/* a song that plays is paused while a video message is recorded and goes on afterwards; default on */
BOOL NoshiChatPauseMusicOnRecord(void);
void NoshiChatSetPauseMusicOnRecord(BOOL on);
/* a song that plays is paused when a video or a video message starts; default on, which is what the app did before the switch existed */
BOOL NoshiChatPauseMusicOnMedia(void);
void NoshiChatSetPauseMusicOnMedia(BOOL on);
/* voice messages are recorded from a Bluetooth headset when one is connected; default off, the built-in microphone */
BOOL NoshiChatRecordViaBluetooth(void);
void NoshiChatSetRecordViaBluetooth(BOOL on);

/* a message that is one emoji is shown large; default on */
BOOL NoshiChatLargeEmoji(void);
void NoshiChatSetLargeEmoji(BOOL on);

/* the tabs of the bottom bar, four of them in either layout: the first is chats, contacts, settings and the profile; the second is contacts, calls, chats and settings */
typedef enum {
    NoshiTabLayoutMessenger = 0,
    NoshiTabLayoutCalls,
    NoshiTabLayoutCount
} NoshiTabLayout;
NoshiTabLayout NoshiTabLayoutStored(void);
void NoshiTabLayoutStore(NoshiTabLayout layout);
void NoshiTabOrderLoad(int order[NOSHI_TAB_SLOTS]);
BOOL NoshiTabOrderStore(const int order[NOSHI_TAB_SLOTS]);
BOOL NoshiTabOrderIsCustom(void);
extern NSString *const NoshiTabOrderDidChangeNotification;

/* what the title of the chat list says: the word Chats, the username, the name of the account, or a text of the person's own */
typedef enum {
    NoshiChatListTitleDefault = 0,
    NoshiChatListTitleUsername,
    NoshiChatListTitleName,
    NoshiChatListTitleCustom,
    NoshiChatListTitleCount
} NoshiChatListTitle;
NoshiChatListTitle NoshiChatListTitleStored(void);
void NoshiChatListTitleStore(NoshiChatListTitle mode);
NSString *NoshiChatListCustomTitle(void);
/* the words a mode puts in the title: the username or name of person when it is known, the person's own text, and the word Chats otherwise */
@class NoshiPerson;
NSString *NoshiChatListTitleText(NoshiChatListTitle mode, NoshiPerson *person);
void NoshiChatListSetCustomTitle(NSString *text);

/* how round the pictures of people and chats are, from 0 (a square) to 100 (a circle); the default is the rounded square the app began with */
#define NOSHI_AVATAR_CORNER_DEFAULT 64
NSInteger NoshiAvatarCornerPercent(void);
void NoshiAvatarCornerStore(NSInteger percent);
/* the outline of the pictures of people and chats, an NoshiShape; the rounded square of the corner above is the default */
NSInteger NoshiAvatarShapeStored(void);
void NoshiAvatarShapeStore(NSInteger shape);
/* the outline of the round button that sends: 0 a circle, 1 a rounded square, 2 the shape of the avatars */
#define NOSHI_SEND_SHAPE_COUNT 3
NSInteger NoshiSendShapeStored(void);
void NoshiSendShapeStore(NSInteger shape);
/* how much of the screen a row of the chat list takes: 0 as it was drawn before the setting, 1 compact */
NSInteger NoshiListDensityStored(void);
void NoshiListDensityStore(NSInteger density);
/* the pill behind the icon of the selected tab of the bottom bar, as the Material navigation bar draws it; off by default */
BOOL NoshiTabIndicatorOn(void);
void NoshiTabIndicatorStore(BOOL on);
/* the look of the classic style, chosen on the customization page. gloss: 0 none, 1 as the style was drawn before the setting, 2 strong. material of the bars: 0 the color of the
   app, 1 steel blue, 2 graphite, 3 black glass. texture of the chat background: 0 linen, 1 a plain color, with its strength in percent (100 is the linen as it was). the
   separators of the lists: 0 a thin line, 1 an etched double line, 2 none */
#define NOSHI_CLASSIC_MATERIAL_COUNT 4
NSInteger NoshiClassicGlossLevel(void);
void NoshiClassicGlossStore(NSInteger level);
NSInteger NoshiClassicMaterial(void);
void NoshiClassicMaterialStore(NSInteger material);
NSInteger NoshiClassicTextureStyle(void);
void NoshiClassicTextureStyleStore(NSInteger style);
NSInteger NoshiClassicTextureStrength(void);
void NoshiClassicTextureStrengthStore(NSInteger percent);
/* the hue of the linen in degrees, or -1 while it follows the accent of the app */
NSInteger NoshiClassicTextureHue(void);
void NoshiClassicTextureHueStore(NSInteger hue);
/* the lit rim and the gloss of the pictures of people, on by default, and a soft shadow under them, off by default */
BOOL NoshiClassicAvatarGloss(void);
void NoshiClassicAvatarGlossStore(BOOL on);
BOOL NoshiClassicAvatarShadow(void);
void NoshiClassicAvatarShadowStore(BOOL on);
NSInteger NoshiClassicSeparators(void);
void NoshiClassicSeparatorsStore(NSInteger style);
/* the classic pictures are kept for a palette, so the choices above are part of what a kept picture is looked up by */
NSString *NoshiClassicLookSignature(void);
/* the corner radius of a card of the settings, from 0 to 36 points */
#define NOSHI_SECTION_RADIUS_DEFAULT 22
#define NOSHI_SECTION_RADIUS_MAX 36
CGFloat NoshiSectionRadius(void);
void NoshiSectionRadiusStore(NSInteger points);

/* how many days the files of messages stay on the phone before the cache removes them; zero keeps them until the cache is full, which is the default */
NSInteger NoshiCacheKeepDays(void);
void NoshiCacheSetKeepDays(NSInteger days);

/* the set a sticker was sent from moves to the front of the panel; default on */
BOOL NoshiChatDynamicPackOrder(void);
void NoshiChatSetDynamicPackOrder(BOOL on);

/* what a swipe to the left on a chat of the list does; the default is the archive, which is what the swipe did before the setting existed */
typedef enum {
    NoshiChatSwipeArchive = 0,
    NoshiChatSwipePin,
    NoshiChatSwipeRead,
    NoshiChatSwipeMute,
    NoshiChatSwipeDelete,
    /* the row has no swipe of its own, so a swipe to the left turns the bar of folders to the next one */
    NoshiChatSwipeFolders
} NoshiChatSwipe;
NoshiChatSwipe NoshiChatSwipeStored(void);

/* what a tab of the folders of the chat list shows: the name, the icon of the folder, or both. exteraGram calls the choices "names only", "icons only" and "names with icons" */
typedef enum {
    NoshiFolderTabsNames = 0,
    NoshiFolderTabsIcons,
    NoshiFolderTabsNamesWithIcons
} NoshiFolderTabStyle;
NoshiFolderTabStyle NoshiFolderTabStyleStored(void);
void NoshiFolderTabStyleStore(NoshiFolderTabStyle style);
/* posted when the style changes, so the bar of folders that is on the screen changes its tabs in place */
extern NSString *const NoshiFolderTabStyleDidChangeNotification;

/* how many seconds a held record button waits before the recording locks by itself; zero never locks it by itself. The choices are 0, 3, 5, 10 and 15, and 5 is the
   default */
NSInteger NoshiChatRecordLockSeconds(void);
void NoshiChatSetRecordLockSeconds(NSInteger seconds);
void NoshiChatSetSwipe(NoshiChatSwipe swipe);

/* back to the defaults of the size and the corners, the "Reset settings" of the menu of the screen */
void NoshiChatResetAppearance(void);
/* whether the size and the corners differ from the defaults, which is when the reset is offered */
BOOL NoshiChatAppearanceChanged(void);

/* the small switches of exteraGram that change one habit of the chat; each has the default of exteraGram, so a
   person who never opens the screen sees the chat as it was */
typedef enum {
    NoshiChatFlagCommaAfterMention = 0,       /* a name picked at the start of the message is followed by a comma */
    NoshiChatFlagRemoveTail,                  /* a classic bubble has no tail */
    NoshiChatFlagEditedIcon,                  /* a pencil in the time line of an edited message instead of the word */
    NoshiChatFlagPollResultsFirst,            /* the votes of a poll show before the account has voted, when the server counted them */
    NoshiChatFlagForwardDate,                 /* the header of a forwarded message names the day the original was written */
    NoshiChatFlagHideShare,
    NoshiChatFlagHideSendAs,                  /* no picture of who the message is sent as beside the field */                   /* no round share button beside the posts of a channel */
    NoshiChatFlagHideStickerTime,             /* no time pill over stickers */
    NoshiChatFlagHideCameraTile,              /* no live camera tile in the attach sheet */
    NoshiChatFlagAlwaysHD,                    /* photos go out in the largest size */
    NoshiChatFlagPauseVoiceOnMinimize,        /* a voice message pauses when the app goes to the background */
    NoshiChatFlagPauseRoundOnMinimize,        /* so does a video message */
    NoshiChatFlagNoAutoNextVoice,             /* a voice message that ends does not start the next one */
    NoshiChatFlagUnmuteWithVolume,            /* a volume button unmutes a muted video */
    NoshiChatFlagSeconds,                     /* the clock under a message has seconds */
    NoshiChatFlagFilterZalgo,                 /* combining marks piled on a letter are cut to a few */
    NoshiChatFlagExactNumbers,                /* 1234 stays 1234 and does not become 1.2K */
    NoshiChatFlagRelativeSeen,                /* "last seen 5 minutes ago" */
    NoshiChatFlagShowIds,                     /* the id and data center in the profile */
    NoshiChatFlagHidePhone,                   /* the number of the account is dots in the settings */
    NoshiChatFlagHideReactionsPrivate,        /* no reactions in chats with a person or a bot */
    NoshiChatFlagHideReactionsGroups,
    NoshiChatFlagHideReactionsChannels,
    NoshiChatFlagMenuCopyPhoto,               /* the entries the menu of a message may add */
    NoshiChatFlagMenuHistory,
    NoshiChatFlagMenuReport,
    NoshiChatFlagMenuNoQuote,
    NoshiChatFlagMenuSave,                    /* "save to favorites", "repeat", "details" and "bookmark" were always in the menu; as in exteraGram they are off until asked for */
    NoshiChatFlagMenuRepeat,
    NoshiChatFlagMenuDetails,
    NoshiChatFlagMenuBookmark,
    NoshiChatFlagMenuRemind,
    NoshiChatFlagMenuReplyPrivate,
    NoshiChatFlagAskCall,                     /* a question before a call starts */
    NoshiChatFlagAskRepeat,                   /* and before "repeat" sends the message again */
    NoshiChatFlagAskRecording,                /* and before a recorded voice or video message goes out */
    NoshiChatFlagAskBotCommand,               /* and before a tapped bot command is sent */
    NoshiChatFlagNoLinkPreview,               /* a message goes out without the preview of the first link in it */
    NoshiChatFlagDeleteForMe,
    NoshiChatFlagReplyColors,                 /* the quote of a reply takes the color of the name of its author; default on */
    NoshiChatFlagReplyBackground,             /* the quote of a reply has a plate under it; default on */                 /* deleting a message in a private chat or a group leaves it with the others */
    NoshiChatFlagLocalPremium,                /* the client shows the Premium features that need no server (custom emoji and reactions, the full animations) */
    NoshiChatFlagSenderAvatars,               /* a small picture of who wrote the last message stands before the preview of a group */
    NoshiChatFlagHideSearchBar,               /* the chat list has no field of search over it */
    NoshiChatFlagHideStories,                 /* the chat list has no strip of stories */
    NoshiChatFlagHideAllChatsTab,             /* the folders of the chat list do not offer the tab of all chats */
    NoshiChatFlagNoUnarchiveSwipe,            /* the swipe of a chat in the archive does nothing, so a chat does not leave it by a slip of the finger */
    NoshiChatFlagHideWaves,                   /* the modern look draws no waves in the corners of the screens */
    NoshiChatFlagShowMessageEmojiStatus,
    NoshiChatFlagShowReplyCustomEmoji,
    NoshiChatFlagBlurWallpaper,               /* a photo set as the wallpaper of the chats is blurred until the person turns the blur off for that wallpaper; on by default, as in Telegram */
    NoshiChatFlagForwardAuthor,               /* a message forwarded without its author goes as a copy that opens with the name and @username of whoever wrote it */
    NoshiChatFlagCount
} NoshiChatFlag;
/* the archive entry of the chat list is hidden on this device, and a pull on the list shows it; the server keeps no such state */
BOOL NoshiArchiveHidden(void);
void NoshiArchiveSetHidden(BOOL hidden);
/* the avatar corner and the card radius are kept in memory; a reset of the stored settings makes them read again */
void NoshiChatSettingsForgetCached(void);
/* whether the account has Premium as far as the client is concerned: the server says so, or the person turned on the local Premium */
BOOL NoshiPremiumEffective(BOOL serverPremium);
BOOL NoshiChatFlagGet(NoshiChatFlag flag);
void NoshiChatFlagSet(NoshiChatFlag flag, BOOL on);

/* whether tapping a link asks first: never, only for a link whose words are not its address, or always */
typedef enum {
    NoshiLinkConfirmNever = 0,
    NoshiLinkConfirmHidden,
    NoshiLinkConfirmAlways
} NoshiLinkConfirm;
NoshiLinkConfirm NoshiChatLinkConfirm(void);
void NoshiChatSetLinkConfirm(NoshiLinkConfirm mode);

/* what a double tap on a message does, once for the messages of others and once for ours; the default is nothing, which leaves a tap undelayed */
typedef enum {
    NoshiDoubleTapNone = 0,
    NoshiDoubleTapReaction,
    NoshiDoubleTapReactionPicker,
    NoshiDoubleTapTranslate,
    NoshiDoubleTapReply,
    NoshiDoubleTapForward,
    NoshiDoubleTapSave,
    NoshiDoubleTapRepeat,
    NoshiDoubleTapEdit,
    NoshiDoubleTapDelete,
    NoshiDoubleTapCount
} NoshiDoubleTapAction;
NoshiDoubleTapAction NoshiChatDoubleTap(BOOL outgoing);
void NoshiChatSetDoubleTap(BOOL outgoing, NoshiDoubleTapAction action);
/* the emoji a double tap reacts with, the red heart until the person picks another; if the chat does not offer it, the first reaction it offers is sent */
/* the double tap that sends the quick reaction can be turned off: the double tap then does nothing, and a single tap stops waiting for a second one. the chosen emoji is kept */
BOOL NoshiChatQuickReactionEnabled(void);
void NoshiChatSetQuickReactionEnabled(BOOL enabled);
NSString *NoshiChatQuickReaction(void);
void NoshiChatSetQuickReaction(NSString *emoji);
NSString *NoshiChatQuickReactionDisplay(void);
void NoshiChatSetQuickCustomReaction(long long documentId, NSString *alt);

/* the jump of a double tap on the left or right half of a video, in seconds: 5, 10, 15 or 30; the default is 10 */
NSInteger NoshiChatSeekSeconds(void);
void NoshiChatSetSeekSeconds(NSInteger seconds);

/* the size of stickers in percent of the usual one, 50 to 130, as the slider of exteraGram; the default is 100 */
#define NOSHI_STICKER_SCALE_MIN 50
#define NOSHI_STICKER_SCALE_MAX 130
NSInteger NoshiChatStickerScale(void);
/* the outline of a sticker in a chat: as it is, with rounded corners, or on a plate shaped like a message bubble; the default is rounded */
typedef enum {
    NoshiStickerShapeNone = 0,
    NoshiStickerShapeRounded,
    NoshiStickerShapeBubble
} NoshiStickerShape;
NoshiStickerShape NoshiChatStickerShape(void);
void NoshiChatSetStickerShape(NoshiStickerShape shape);
void NoshiChatSetStickerScale(NSInteger percent);
