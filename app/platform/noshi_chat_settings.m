#import "noshi_chat_settings.h"
#import "noshi_person.h"

#import "noshi_platform.h"
#import "noshi_theme.h"
#include "noshi_reactions.h"

NSString *const NoshiChatSettingsDidChangeNotification = @"NoshiChatSettingsDidChange";

static NSString *const NoshiChatTextSizeKey = @"noshigram.chat.textsize";
static NSString *const NoshiChatBubbleRadiusKey = @"noshigram.chat.bubbleradius";
static NSString *const NoshiChatListStyleKey = @"noshigram.chat.liststyle";
static NSString *const NoshiChatSendByEnterKey = @"noshigram.chat.sendbyenter";
static NSString *const NoshiChatNextMediaTapKey = @"noshigram.chat.nextmediatap";
static NSString *const NoshiChatRaiseToListenKey = @"noshigram.chat.raisetolisten";
static NSString *const NoshiChatRaiseToSpeakKey = @"noshigram.chat.raisetospeak";
static NSString *const NoshiChatPauseOnRecordKey = @"noshigram.chat.pauseonrecord";
static NSString *const NoshiChatPauseOnMediaKey = @"noshigram.chat.pauseonmedia";
static NSString *const NoshiChatBluetoothKey = @"noshigram.chat.bluetoothmic";
static NSString *const NoshiChatSwipeKey = @"noshigram.chat.swipe";
static NSString *const NoshiChatLargeEmojiKey = @"noshigram.chat.largeemoji";
static NSString *const NoshiChatListTitleKey = @"noshigram.chatlist.title";
static NSString *const NoshiChatListCustomTitleKey = @"noshigram.chatlist.customtitle";
static NSString *const NoshiListDensityKey = @"noshigram.list.density";
static NSString *const NoshiTabIndicatorKey = @"noshigram.tab.indicator";
static NSString *const NoshiClassicSeparatorsKey = @"noshigram.classic.separators";
static NSString *const NoshiSectionRadiusKey = @"noshigram.section.radius";
static NSString *const NoshiTabContactsHiddenKey = @"noshigram.tab.contacts.hidden";
static NSString *const NoshiTabCallsHiddenKey = @"noshigram.tab.calls.hidden";
NSString *const NoshiTabsDidChangeNotification = @"NoshiTabsDidChange";
static NSString *const NoshiCacheKeepDaysKey = @"noshigram.cache.keepdays";
static NSString *const NoshiChatDynamicPackOrderKey = @"noshigram.chat.dynamicpackorder";

static NSInteger NoshiClamped(NSInteger value, NSInteger low, NSInteger high) {
    return value < low ? low : (value > high ? high : value);
}

/* a stored number, or nil when the key was never written (zero is a real radius, so the default cannot stand for "unset") */
static NSNumber *NoshiStoredNumber(NSString *key) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

/* TRACE: temporary, appends one line per write to a file in the temporary folder of the app */
static void NoshiTrace(NSString *line) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"chatset-trace.txt"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[NSString stringWithFormat:@"%.3f %@\n", CFAbsoluteTimeGetCurrent() - 780000000, line] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

void NoshiChatTrace(NSString *line) { NoshiTrace(line); }

static void NoshiStoreNumber(NSString *key, NSInteger value) {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    NoshiTrace([NSString stringWithFormat:@"store %@ = %ld, reads %@", key, (long)value, [[NSUserDefaults standardUserDefaults] objectForKey:key]]);
    NoshiDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
}

NSInteger NoshiChatDefaultTextSize(void) {
    return NoshiIsPad() ? 18 : 16;
}

NSInteger NoshiChatTextSize(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatTextSizeKey);
    return stored ? NoshiClamped(stored.integerValue, NOSHI_CHAT_TEXT_SIZE_MIN, NOSHI_CHAT_TEXT_SIZE_MAX) : NoshiChatDefaultTextSize();
}

void NoshiChatSetTextSize(NSInteger size) {
    NoshiStoreNumber(NoshiChatTextSizeKey, NoshiClamped(size, NOSHI_CHAT_TEXT_SIZE_MIN, NOSHI_CHAT_TEXT_SIZE_MAX));
}

NSInteger NoshiChatBubbleRadius(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatBubbleRadiusKey);
    return stored ? NoshiClamped(stored.integerValue, NOSHI_CHAT_BUBBLE_RADIUS_MIN, NOSHI_CHAT_BUBBLE_RADIUS_MAX) : NOSHI_CHAT_BUBBLE_RADIUS_MAX;
}

void NoshiChatSetBubbleRadius(NSInteger radius) {
    NoshiStoreNumber(NoshiChatBubbleRadiusKey, NoshiClamped(radius, NOSHI_CHAT_BUBBLE_RADIUS_MIN, NOSHI_CHAT_BUBBLE_RADIUS_MAX));
}

NSInteger NoshiChatClassicBubbleRadius(void) {
    return (NoshiChatBubbleRadius() * 15 + NOSHI_CHAT_BUBBLE_RADIUS_MAX / 2) / NOSHI_CHAT_BUBBLE_RADIUS_MAX;
}

NoshiChatListStyle NoshiChatListStyleStored(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatListStyleKey);
    return stored && stored.integerValue == NoshiChatListTwoLines ? NoshiChatListTwoLines : NoshiChatListThreeLines;
}

void NoshiChatSetListStyle(NoshiChatListStyle style) {
    NoshiStoreNumber(NoshiChatListStyleKey, style == NoshiChatListTwoLines ? NoshiChatListTwoLines : NoshiChatListThreeLines);
}

/* a switch: the stored value, or the default while the key was never written */
static BOOL NoshiStoredFlag(NSString *key, BOOL fallback) {
    NSNumber *stored = NoshiStoredNumber(key);
    return stored ? stored.boolValue : fallback;
}

static void NoshiStoreFlag(NSString *key, BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
    NoshiDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
}

BOOL NoshiChatSendByEnter(void) { return NoshiStoredFlag(NoshiChatSendByEnterKey, NO); }
void NoshiChatSetSendByEnter(BOOL on) { NoshiStoreFlag(NoshiChatSendByEnterKey, on); }
BOOL NoshiChatNextMediaTap(void) { return NoshiStoredFlag(NoshiChatNextMediaTapKey, NO); }
void NoshiChatSetNextMediaTap(BOOL on) { NoshiStoreFlag(NoshiChatNextMediaTapKey, on); }
BOOL NoshiChatRaiseToListen(void) { return NoshiStoredFlag(NoshiChatRaiseToListenKey, YES); }
void NoshiChatSetRaiseToListen(BOOL on) { NoshiStoreFlag(NoshiChatRaiseToListenKey, on); }
BOOL NoshiChatRaiseToSpeak(void) { return NoshiStoredFlag(NoshiChatRaiseToSpeakKey, NO); }
void NoshiChatSetRaiseToSpeak(BOOL on) { NoshiStoreFlag(NoshiChatRaiseToSpeakKey, on); }
BOOL NoshiChatPauseMusicOnRecord(void) { return NoshiStoredFlag(NoshiChatPauseOnRecordKey, YES); }
void NoshiChatSetPauseMusicOnRecord(BOOL on) { NoshiStoreFlag(NoshiChatPauseOnRecordKey, on); }
BOOL NoshiChatPauseMusicOnMedia(void) { return NoshiStoredFlag(NoshiChatPauseOnMediaKey, YES); }
void NoshiChatSetPauseMusicOnMedia(BOOL on) { NoshiStoreFlag(NoshiChatPauseOnMediaKey, on); }
/* the key is the one the list wrote before the setting had a page of its own */
static NSString *const NoshiArchiveHiddenKey = @"NoshiArchiveHidden";
BOOL NoshiPremiumEffective(BOOL serverPremium) { return serverPremium || NoshiChatFlagGet(NoshiChatFlagLocalPremium); }
BOOL NoshiArchiveHidden(void) { return NoshiStoredFlag(NoshiArchiveHiddenKey, NO); }
void NoshiArchiveSetHidden(BOOL hidden) { NoshiStoreFlag(NoshiArchiveHiddenKey, hidden); }
BOOL NoshiChatLargeEmoji(void) { return NoshiStoredFlag(NoshiChatLargeEmojiKey, YES); }
void NoshiChatSetLargeEmoji(BOOL on) { NoshiStoreFlag(NoshiChatLargeEmojiKey, on); }
NoshiChatListTitle NoshiChatListTitleStored(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatListTitleKey);
    return stored && stored.integerValue >= 0 && stored.integerValue < NoshiChatListTitleCount ? (NoshiChatListTitle)stored.integerValue : NoshiChatListTitleDefault;
}
void NoshiChatListTitleStore(NoshiChatListTitle mode) { NoshiStoreNumber(NoshiChatListTitleKey, mode); }
NSString *NoshiChatListCustomTitle(void) {
    NSString *text = [[NSUserDefaults standardUserDefaults] stringForKey:NoshiChatListCustomTitleKey];
    return text ? text : @"";
}
NSString *NoshiChatListTitleText(NoshiChatListTitle mode, NoshiPerson *person) {
    switch (mode) {
    case NoshiChatListTitleUsername:
        if (person.username.length) return [@"@" stringByAppendingString:person.username];
        break;
    case NoshiChatListTitleName:
        if (person.name.length) return person.name;
        break;
    case NoshiChatListTitleCustom: {
        NSString *text = [NoshiChatListCustomTitle() stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length) return text;
        break;
    }
    case NoshiChatListTitleDefault:
    case NoshiChatListTitleCount:
        break;
    }
    return NSLocalizedString(@"chats.title", nil);
}
void NoshiChatListSetCustomTitle(NSString *text) {
    [[NSUserDefaults standardUserDefaults] setObject:text ? text : @"" forKey:NoshiChatListCustomTitleKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the title of the chat list was not saved");
}

NSInteger NoshiListDensityStored(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiListDensityKey);
    return stored ? NoshiClamped(stored.integerValue, 0, 1) : 0;
}
void NoshiListDensityStore(NSInteger density) {
    NoshiStoreNumber(NoshiListDensityKey, NoshiClamped(density, 0, 1));
}
BOOL NoshiTabIndicatorOn(void) {
    return [NoshiStoredNumber(NoshiTabIndicatorKey) boolValue];
}
void NoshiTabIndicatorStore(BOOL on) {
    NoshiStoreNumber(NoshiTabIndicatorKey, on ? 1 : 0);
}
/* the lists read this at every configure, so it is kept in memory and changed with the stored value. the version that also had an etched line stored 0 thin, 1 etched
   and 2 none; the etched line is read as the thin one */
static NSInteger NoshiClassicSeparatorsCurrent = -1;
NSInteger NoshiClassicSeparators(void) {
    if (NoshiClassicSeparatorsCurrent < 0) {
        NSNumber *stored = NoshiStoredNumber(NoshiClassicSeparatorsKey);
        NoshiClassicSeparatorsCurrent = stored && stored.integerValue >= 2 ? 1 : 0;
    }
    return NoshiClassicSeparatorsCurrent;
}
void NoshiClassicSeparatorsStore(NSInteger style) {
    NoshiClassicSeparatorsCurrent = style ? 1 : 0;
    NoshiStoreNumber(NoshiClassicSeparatorsKey, NoshiClassicSeparatorsCurrent ? 2 : 0);
}
static NSInteger NoshiSectionRadiusCurrent = -1;
CGFloat NoshiSectionRadius(void) {
    if (NoshiSectionRadiusCurrent < 0) {
        NSNumber *stored = NoshiStoredNumber(NoshiSectionRadiusKey);
        NoshiSectionRadiusCurrent = stored && stored.integerValue >= 0 && stored.integerValue <= NOSHI_SECTION_RADIUS_MAX ? stored.integerValue : NOSHI_SECTION_RADIUS_DEFAULT;
    }
    return (CGFloat)NoshiSectionRadiusCurrent;
}
void NoshiSectionRadiusStore(NSInteger points) {
    NoshiSectionRadiusCurrent = MAX(0, MIN(NOSHI_SECTION_RADIUS_MAX, points));
    NoshiStoreNumber(NoshiSectionRadiusKey, NoshiSectionRadiusCurrent);
}
BOOL NoshiTabShown(NoshiTabKind kind) {
    if (kind == NoshiTabContacts) return !NoshiStoredFlag(NoshiTabContactsHiddenKey, NO);
    if (kind == NoshiTabCalls) return !NoshiStoredFlag(NoshiTabCallsHiddenKey, NO);
    return kind < NoshiTabKindCount;
}
void NoshiTabSetShown(NoshiTabKind kind, BOOL shown) {
    if (kind == NoshiTabContacts) NoshiStoreFlag(NoshiTabContactsHiddenKey, !shown);
    else if (kind == NoshiTabCalls) NoshiStoreFlag(NoshiTabCallsHiddenKey, !shown);
    else return;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiTabsDidChangeNotification object:nil];
}
NSInteger NoshiCacheKeepDays(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiCacheKeepDaysKey);
    return stored && stored.integerValue > 0 && stored.integerValue <= 365 ? stored.integerValue : 0;
}
void NoshiCacheSetKeepDays(NSInteger days) { NoshiStoreNumber(NoshiCacheKeepDaysKey, days); }
BOOL NoshiChatDynamicPackOrder(void) { return NoshiStoredFlag(NoshiChatDynamicPackOrderKey, YES); }
void NoshiChatSetDynamicPackOrder(BOOL on) { NoshiStoreFlag(NoshiChatDynamicPackOrderKey, on); }
BOOL NoshiChatRecordViaBluetooth(void) { return NoshiStoredFlag(NoshiChatBluetoothKey, NO); }
void NoshiChatSetRecordViaBluetooth(BOOL on) { NoshiStoreFlag(NoshiChatBluetoothKey, on); }

static const struct { NSString *key; BOOL fallback; } NoshiChatFlagTable[NoshiChatFlagCount] = {
    [NoshiChatFlagCommaAfterMention] = {@"noshigram.chat.mentioncomma", NO},
    [NoshiChatFlagRemoveTail] = {@"noshigram.chat.notail", NO},
    [NoshiChatFlagEditedIcon] = {@"noshigram.chat.editedicon", NO},
    [NoshiChatFlagPollResultsFirst] = {@"noshigram.chat.pollresultsfirst", NO},
    [NoshiChatFlagForwardDate] = {@"noshigram.chat.forwarddate", NO},
    [NoshiChatFlagForwardAuthor] = {@"noshigram.chat.forwardauthor", NO},
    [NoshiChatFlagHideShare] = {@"noshigram.chat.hideshare", NO},
    [NoshiChatFlagHideSendAs] = {@"noshigram.chat.hidesendas", NO},
    [NoshiChatFlagHideStickerTime] = {@"noshigram.chat.hidestickertime", NO},
    [NoshiChatFlagHideCameraTile] = {@"noshigram.chat.hidecameratile", NO},
    [NoshiChatFlagAlwaysHD] = {@"noshigram.chat.alwayshd", NO},
    [NoshiChatFlagPauseVoiceOnMinimize] = {@"noshigram.chat.pausevoice", NO},
    [NoshiChatFlagPauseRoundOnMinimize] = {@"noshigram.chat.pauseround", NO},
    [NoshiChatFlagNoAutoNextVoice] = {@"noshigram.chat.noautonextvoice", NO},
    [NoshiChatFlagUnmuteWithVolume] = {@"noshigram.chat.unmutevolume", NO},
    [NoshiChatFlagSeconds] = {@"noshigram.chat.seconds", NO},
    [NoshiChatFlagFilterZalgo] = {@"noshigram.chat.zalgo", NO},
    [NoshiChatFlagExactNumbers] = {@"noshigram.chat.exactnumbers", NO},
    [NoshiChatFlagRelativeSeen] = {@"noshigram.chat.relativeseen", NO},
    [NoshiChatFlagShowIds] = {@"noshigram.chat.showids", NO},
    [NoshiChatFlagHidePhone] = {@"noshigram.chat.hidephone", NO},
    [NoshiChatFlagHideReactionsPrivate] = {@"noshigram.chat.noreactionsprivate", NO},
    [NoshiChatFlagHideReactionsGroups] = {@"noshigram.chat.noreactionsgroups", NO},
    [NoshiChatFlagHideReactionsChannels] = {@"noshigram.chat.noreactionschannels", NO},
    [NoshiChatFlagMenuCopyPhoto] = {@"noshigram.chat.menucopyphoto", NO},
    [NoshiChatFlagMenuHistory] = {@"noshigram.chat.menuhistory", NO},
    [NoshiChatFlagMenuReport] = {@"noshigram.chat.menureport", NO},
    [NoshiChatFlagMenuNoQuote] = {@"noshigram.chat.menunoquote", NO},
    [NoshiChatFlagMenuSave] = {@"noshigram.chat.menusave", NO},
    [NoshiChatFlagMenuRepeat] = {@"noshigram.chat.menurepeat", NO},
    [NoshiChatFlagMenuDetails] = {@"noshigram.chat.menudetails", NO},
    [NoshiChatFlagMenuBookmark] = {@"noshigram.chat.menubookmark", NO},
    [NoshiChatFlagMenuRemind] = {@"noshigram.chat.menuremind", NO},
    [NoshiChatFlagMenuReplyPrivate] = {@"noshigram.chat.menureplyprivate", NO},
    [NoshiChatFlagAskCall] = {@"noshigram.chat.askcall", NO},
    [NoshiChatFlagAskRepeat] = {@"noshigram.chat.askrepeat", NO},
    [NoshiChatFlagAskRecording] = {@"noshigram.chat.askrecording", NO},
    [NoshiChatFlagAskBotCommand] = {@"noshigram.chat.askbotcommand", NO},
    [NoshiChatFlagNoLinkPreview] = {@"noshigram.chat.nolinkpreview", NO},
    [NoshiChatFlagDeleteForMe] = {@"noshigram.chat.deleteforme", NO},
    [NoshiChatFlagReplyColors] = {@"noshigram.chat.replycolors", YES},
    [NoshiChatFlagReplyBackground] = {@"noshigram.chat.replybackground", YES},
    [NoshiChatFlagLocalPremium] = {@"noshigram.chat.localpremium", NO},
    [NoshiChatFlagHideWaves] = {@"noshigram.chat.hidewaves", NO},
    [NoshiChatFlagShowMessageEmojiStatus] = {@"noshigram.chat.messageemojistatus", YES},
    [NoshiChatFlagShowReplyCustomEmoji] = {@"noshigram.chat.replycustomemoji", YES},
    [NoshiChatFlagSenderAvatars] = {@"noshigram.chat.senderavatars", NO},
    [NoshiChatFlagHideSearchBar] = {@"noshigram.chat.hidesearch", NO},
    [NoshiChatFlagHideStories] = {@"noshigram.chat.hidestories", NO},
    [NoshiChatFlagHideAllChatsTab] = {@"noshigram.chat.hidealltab", NO},
    [NoshiChatFlagNoUnarchiveSwipe] = {@"noshigram.chat.nounarchiveswipe", NO},
    [NoshiChatFlagBlurWallpaper] = {@"noshigram.chat.blurwallpaper", YES},
};

BOOL NoshiChatFlagGet(NoshiChatFlag flag) {
    if ((NSUInteger)flag >= NoshiChatFlagCount) return NO;
    return NoshiStoredFlag(NoshiChatFlagTable[flag].key, NoshiChatFlagTable[flag].fallback);
}

void NoshiChatFlagSet(NoshiChatFlag flag, BOOL on) {
    if ((NSUInteger)flag >= NoshiChatFlagCount) return;
    NoshiStoreFlag(NoshiChatFlagTable[flag].key, on);
}

static NSString *const NoshiChatLinkConfirmKey = @"noshigram.chat.linkconfirm";

NoshiLinkConfirm NoshiChatLinkConfirm(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatLinkConfirmKey);
    NSInteger value = stored ? stored.integerValue : NoshiLinkConfirmNever;
    return value == NoshiLinkConfirmHidden || value == NoshiLinkConfirmAlways ? (NoshiLinkConfirm)value : NoshiLinkConfirmNever;
}

void NoshiChatSetLinkConfirm(NoshiLinkConfirm mode) {
    NoshiStoreNumber(NoshiChatLinkConfirmKey, mode);
}

static NSString *const NoshiChatDoubleTapInKey = @"noshigram.chat.doubletap.in";
static NSString *const NoshiChatDoubleTapOutKey = @"noshigram.chat.doubletap.out";
static NSString *const NoshiChatSeekKey = @"noshigram.chat.seek";
static NSString *const NoshiChatStickerScaleKey = @"noshigram.chat.stickerscale";
static NSString *const NoshiChatStickerShapeKey = @"noshigram.chat.stickershape";

static NSString *const NoshiChatQuickReactionOffKey = @"noshigram.chat.quickreaction.off";

BOOL NoshiChatQuickReactionEnabled(void) {
    NSNumber *off = NoshiStoredNumber(NoshiChatQuickReactionOffKey);
    return !off.integerValue;
}

void NoshiChatSetQuickReactionEnabled(BOOL enabled) {
    NoshiStoreNumber(NoshiChatQuickReactionOffKey, enabled ? 0 : 1);
}

NoshiDoubleTapAction NoshiChatDoubleTap(BOOL outgoing) {
    NSNumber *stored = NoshiStoredNumber(outgoing ? NoshiChatDoubleTapOutKey : NoshiChatDoubleTapInKey);
    /* reacts to a double tap out of the box */
    NSInteger value = stored ? stored.integerValue : NoshiDoubleTapReaction;
    if (value == NoshiDoubleTapReaction && !NoshiChatQuickReactionEnabled()) return NoshiDoubleTapNone;
    return value >= NoshiDoubleTapNone && value < NoshiDoubleTapCount ? (NoshiDoubleTapAction)value : NoshiDoubleTapNone;
}

static NSString *const NoshiChatQuickReactionKey = @"noshigram.chat.quickreaction";

NSString *NoshiChatQuickReaction(void) {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:NoshiChatQuickReactionKey];
    return stored.length ? stored : @"\u2764";
}

void NoshiChatSetQuickReaction(NSString *emoji) {
    if (emoji.length) [[NSUserDefaults standardUserDefaults] setObject:emoji forKey:NoshiChatQuickReactionKey];
}

NSString *NoshiChatQuickReactionDisplay(void) {
    if (!noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String)) return NoshiChatQuickReaction();
    NSString *alt = [[NSUserDefaults standardUserDefaults] stringForKey:@"noshigram.chat.quickreaction.alt"];
    return alt.length ? alt : @"✨";
}

void NoshiChatSetQuickCustomReaction(long long documentId, NSString *alt) {
    if (documentId <= 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:alt.length ? alt : @"✨" forKey:@"noshigram.chat.quickreaction.alt"];
    NoshiChatSetQuickReaction([NSString stringWithFormat:@"animated_%lld", documentId]);
}

void NoshiChatSetDoubleTap(BOOL outgoing, NoshiDoubleTapAction action) {
    NoshiStoreNumber(outgoing ? NoshiChatDoubleTapOutKey : NoshiChatDoubleTapInKey, action);
}

NSInteger NoshiChatSeekSeconds(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatSeekKey);
    NSInteger value = stored ? stored.integerValue : 10;
    return value == 5 || value == 10 || value == 15 || value == 30 ? value : 10;
}

void NoshiChatSetSeekSeconds(NSInteger seconds) {
    NoshiStoreNumber(NoshiChatSeekKey, seconds == 5 || seconds == 15 || seconds == 30 ? seconds : 10);
}

NSInteger NoshiChatStickerScale(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatStickerScaleKey);
    return stored ? NoshiClamped(stored.integerValue, NOSHI_STICKER_SCALE_MIN, NOSHI_STICKER_SCALE_MAX) : 100;
}

void NoshiChatSetStickerScale(NSInteger percent) {
    NoshiStoreNumber(NoshiChatStickerScaleKey, NoshiClamped(percent, NOSHI_STICKER_SCALE_MIN, NOSHI_STICKER_SCALE_MAX));
}

NoshiStickerShape NoshiChatStickerShape(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatStickerShapeKey);
    NSInteger value = stored ? stored.integerValue : NoshiStickerShapeRounded;
    return value >= NoshiStickerShapeNone && value <= NoshiStickerShapeBubble ? (NoshiStickerShape)value : NoshiStickerShapeRounded;
}

void NoshiChatSetStickerShape(NoshiStickerShape shape) {
    NoshiStoreNumber(NoshiChatStickerShapeKey, shape);
}

NoshiChatSwipe NoshiChatSwipeStored(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatSwipeKey);
    NSInteger value = stored ? stored.integerValue : NoshiChatSwipeArchive;
    return value >= NoshiChatSwipeArchive && value <= NoshiChatSwipeFolders ? (NoshiChatSwipe)value : NoshiChatSwipeArchive;
}

static NSString *const NoshiFolderTabStyleKey = @"noshigram.chat.foldertabs";
NSString *const NoshiFolderTabStyleDidChangeNotification = @"NoshiFolderTabStyleDidChange";

NoshiFolderTabStyle NoshiFolderTabStyleStored(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiFolderTabStyleKey);
    NSInteger value = stored ? stored.integerValue : NoshiFolderTabsNames;
    return value >= NoshiFolderTabsNames && value <= NoshiFolderTabsNamesWithIcons ? (NoshiFolderTabStyle)value : NoshiFolderTabsNames;
}

void NoshiFolderTabStyleStore(NoshiFolderTabStyle style) {
    if (style == NoshiFolderTabStyleStored()) return;
    NoshiStoreNumber(NoshiFolderTabStyleKey, style);
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiFolderTabStyleDidChangeNotification object:nil];
}

static NSString *const NoshiChatRecordLockKey = @"noshigram.chat.recordlock";

NSInteger NoshiChatRecordLockSeconds(void) {
    NSNumber *stored = NoshiStoredNumber(NoshiChatRecordLockKey);
    if (!stored) return 5;
    NSInteger value = stored.integerValue;
    return value == 0 || value == 3 || value == 5 || value == 10 || value == 15 ? value : 5;
}

void NoshiChatSetRecordLockSeconds(NSInteger seconds) {
    NoshiStoreNumber(NoshiChatRecordLockKey, seconds);
}

void NoshiChatSetSwipe(NoshiChatSwipe swipe) {
    NoshiStoreNumber(NoshiChatSwipeKey, swipe);
}

void NoshiChatResetAppearance(void) {
    NoshiTrace(@"RESET appearance");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiChatTextSizeKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiChatBubbleRadiusKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the chat appearance was not reset on disk");
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
}

BOOL NoshiChatAppearanceChanged(void) {
    return NoshiChatTextSize() != NoshiChatDefaultTextSize() || NoshiChatBubbleRadius() != NOSHI_CHAT_BUBBLE_RADIUS_MAX;
}

void NoshiChatSettingsForgetCached(void) {
    NoshiSectionRadiusCurrent = -1;
}
