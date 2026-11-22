#import "noshi_download_log.h"
#import "noshi_alert_view.h"
#import "noshi_gift_detail_controller.h"
#import "noshi_emoji_label.h"
#import "noshi_pinned_line.h"
#import "noshi_round_glow.h"
#import "noshi_chat_controller.h"
#import "noshi_message_effect_player.h"
#import "noshi_saved_media_controller.h"
#import "noshi_send_as_menu.h"
#import "noshi_send_menu.h"
#import "noshi_group_call_engine.h"
#import "noshi_location_controller.h"
#import "noshi_status_label.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_text_parts.h"
#include "noshi_text_split.h"
#import "noshi_session_privacy.h"
#import "noshi_chat_search.h"
#import "noshi_attach_flow.h"
#import "noshi_image_decoder.h"
#import "noshi_attach_sheet.h"
#import "noshi_avatar_view.h"
#import "noshi_story_ring.h"
#import "noshi_bar_button.h"
#import "noshi_chat_bots.h"
#import "noshi_chat_item.h"
#import "noshi_classic_chrome.h"
#import "noshi_connecting_label.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_topic_icon.h"
#import "noshi_voice_transcriber.h"
#import "noshi_mini_player.h"
#import "noshi_next_chat_hint.h"
#import "noshi_topics_screen.h"
#import "noshi_name_badge.h"
#import "noshi_peer_colors.h"
#import "noshi_gift_catalog_controller.h"
#import "noshi_report_flow.h"
#import "noshi_compose_context.h"
#import "noshi_dialog_picker_controller.h"
#import "noshi_session_actions.h"
#import "noshi_settings_kit.h"
#import "noshi_session_sendas.h"
#import "noshi_sticker_maker.h"
#import "noshi_sheet.h"
#import "noshi_selection_bar.h"
#import "noshi_gallery_saver.h"
#import "noshi_bookmark_store.h"
#import "noshi_message_menu.h"
#import "noshi_sheet.h"
#import "noshi_bookmarks_controller.h"
#include "noshi_message_actions.h"
#import "noshi_gift_screen.h"
#import "noshi_forward.h"
#import "noshi_gifts_controller.h"
#import "noshi_channel_profile_controller.h"
#import "noshi_plural.h"
#import "noshi_greeting_view.h"
#import "noshi_premium_gate_view.h"
#import "noshi_session_channels.h"
#import "noshi_user_profile_controller.h"
#import "noshi_input_bar.h"
#import "noshi_link_router.h"
#import "noshi_input_panel.h"
#import "noshi_sticker_pack_sheet.h"
#import "noshi_media_viewer.h"
#import "noshi_message_cell.h"
#import "noshi_reaction_time_popup.h"
#import "noshi_chat_settings.h"
#import "noshi_music_player.h"
#import "noshi_round_playback.h"
#import "noshi_voice.h"
#import "noshi_proximity.h"
#import "noshi_popup_menu.h"
#import "noshi_session_profile.h"
#import "noshi_reaction_picker.h"
#import "noshi_reaction_people_controller.h"
#import "noshi_message_stats_controller.h"
#import "noshi_back_swipe.h"
#import "noshi_round_recorder.h"
#import "noshi_voice_recorder.h"
#import "noshi_person.h"
#import "noshi_message_report_flow.h"
#import "noshi_app_sounds.h"
#import "noshi_notifications_chat_controller.h"
#import "noshi_notifier.h"
#import "noshi_platform.h"
#import "noshi_session_stickermanage.h"
#import "noshi_split_controller.h"
#import "noshi_theme.h"
#import "noshi_language.h"
#import "noshi_lite_mode.h"
#import "noshi_animation.h"
#import "noshi_typing_bubble.h"
#import "noshi_draft.h"
#import "noshi_dust_effect.h"
#import "noshi_session_drafts.h"
#import "noshi_translate_config.h"
#import "noshi_translator.h"
#import "noshi_wallpaper.h"
#import "noshi_chat_list.h"
#import "noshi_wallpaper_controller.h"
#import "noshi_time.h"
#include "noshi_scroll.h"
#import "noshi_weak_reference.h"
#import "noshi_welcome_toast.h"
#import "noshi_reaction_artwork.h"
#import "noshi_reaction_effect.h"

#define BAR_HEIGHT 44.0
/* what the buttons on the wider side of the classic bar of a chat take of a phone's width: the picture and the dots, or the arrow and a count of three digits */
#define CLASSIC_BAR_SIDE_WIDTH 96.0
/* the back plate and the gap before the count beside it; with the count itself they are what the bar gives the left side */
#define CLASSIC_BACK_PLATE 52.0
#define CLASSIC_COUNTER_GAP 8.0
/* what a reaction that is new on a message plays once its chip stands: nothing, the 80 point burst or the large one of the picker */
#define NOSHI_BURST_NONE 0
#define NOSHI_BURST_SHORT 1
#define NOSHI_BURST_LONG 2
#define PINNED_HEIGHT 46.0
#define PINNED_FOOT_TAG 9146
#define VOICE_HEIGHT 44.0
/* the pages of older history a tap on the pinned message will fetch looking for it */
#define PINNED_SEARCH_PAGES 12
#define HISTORY_PAGE 40
/* a page of older history: every page costs a walk over all loaded messages on the main thread, so a longer one means fewer walks while the list is read upwards through a big chat */
#define OLDER_PAGE 80
/* rows below or above the fold whose pictures are fetched ahead, nearest first */
static NSString *NoshiMessageSummary(NoshiMessage *message);

#define PREPARE_ROWS_MAX 6
/* a deletion or a new message of more rows than this is a reload of the chat, not an event worth an effect */
#define DUST_ROWS_MAX 4
#define ENTER_ROWS_MAX 3
/* rows one change may tell the table about row by row; more than this is one reload */
#define BULK_ROWS_MAX 40
#define GROUP_GAP_SECONDS 300

@interface NoshiChatController (ReactionPolling)
- (void)pollReactions;
- (void)flushLiveMessages;
- (void)advanceBottom:(CADisplayLink *)link;
@end

/* NSTimer retains its target, the weak bridge lets a removed chat release its timer */
@interface NoshiReactionPollTarget : NSObject {
    NoshiWeakReference *_weak;
}
- (id)initWithReference:(NoshiWeakReference *)weak;
- (void)fire:(NSTimer *)timer;
@end

@implementation NoshiReactionPollTarget
- (id)initWithReference:(NoshiWeakReference *)weak {
    self = [super init];
    if (self) _weak = [weak retain];
    return self;
}
- (void)dealloc { [_weak release]; [super dealloc]; }
- (void)fire:(NSTimer *)timer { (void)timer; [(NoshiChatController *)_weak.target pollReactions]; }
- (void)display:(CADisplayLink *)link { (void)link; [(NoshiChatController *)_weak.target flushLiveMessages]; }
- (void)follow:(CADisplayLink *)link { [(NoshiChatController *)_weak.target advanceBottom:link]; }
- (void)jump:(CADisplayLink *)link { [(NoshiChatController *)_weak.target advanceJump:link]; }
@end

@interface NoshiReaderRowView : UIView {
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_name;
    NoshiEmojiLabel *_time;
    NoshiPerson *_person;
    NoshiAvatarCache *_cache;
}
- (id)initWithPerson:(NoshiPerson *)person userId:(long long)userId name:(NSString *)name time:(NSString *)time cache:(NoshiAvatarCache *)cache;
@end

@implementation NoshiReaderRowView
- (id)initWithPerson:(NoshiPerson *)person userId:(long long)userId name:(NSString *)name time:(NSString *)time cache:(NoshiAvatarCache *)cache {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _person = [person retain];
    _cache = [cache retain];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.seed = (NSUInteger)(userId % 1000003);
    _avatar.initials = person ? person.initials : NoshiInitialsOfName(name);
    _avatar.deleted = person.deleted;
    [self addSubview:_avatar];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.font = NoshiFontSemibold(16);
    _name.textColor = NoshiColorTitle();
    _name.dropsUndrawable = YES;
    _name.text = name;
    [self addSubview:_name];
    _time = [[NoshiEmojiLabel alloc] init];
    _time.font = NoshiFontRegular(14);
    _time.textColor = NoshiColorSecondary();
    _time.text = time;
    [self addSubview:_time];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, time];
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [_avatar setPhoto:_person.photo cache:_cache];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _avatar.frame = CGRectMake(12, 10, 44, 44);
    _name.frame = CGRectMake(68, 8, MAX(0, self.bounds.size.width - 80), 24);
    _time.frame = CGRectMake(68, 32, MAX(0, self.bounds.size.width - 80), 22);
}
- (void)dealloc {
    [_avatar release];
    [_name release];
    [_time release];
    [_person release];
    [_cache release];
    [super dealloc];
}
@end

@interface NoshiChatController () <NoshiBackSwipeBlocking, UITableViewDataSource, UITableViewDelegate, NoshiInputBarDelegate, NoshiInputPanelDelegate, NoshiAttachSheetDelegate,
                                      NoshiMessageCellDelegate, NoshiRoundChain, UIAlertViewDelegate, NoshiChatBotsHost, UIDocumentInteractionControllerDelegate> {
    UIDocumentInteractionController *_document;
    NoshiSession *_session;
    NoshiDialog *_dialog;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;

    UIImageView *_wallpaper;
    NSString *_channelWallpaperSignature;
    BOOL _channelFullFailed;
    NSUInteger _codeCopyToken;
    NoshiMiniPlayer *_miniPlayer;
    UITableView *_table;
    BOOL _premium;
    BOOL _premiumKnown;
    BOOL _serverPremium;
    BOOL _reactionLimitsKnown;
    int32_t _reactionLimitStandard;
    int32_t _reactionLimitPremium;
    NoshiWelcomeToast *_reactionPromo;
    /* this account as a person, asked for once when a chip first needs its picture */
    NoshiPerson *_selfPerson;
    BOOL _selfPersonAsked;
    /* the id of this account, read from its file once */
    NSNumber *_accountId;
    UIView *_header;
    UIView *_headerLine;
    UIButton *_back;
    /* the unread messages of the other chats, over the arrow that goes back to them */
    UILabel *_backBadge;
    /* the classic style: the way back is made here, as an arrow with the count (or the name of the list when nothing is unread), and the system one hidden */
    BOOL _classicBack;
    /* the width of the count that stands beside the back arrow of the classic bar, zero without one */
    CGFloat _classicCounterWidth;
    NoshiAvatarView *_avatar;
    /* the bar of a forum topic shows the icon of the topic where a chat shows the picture of the person or the group */
    UIImageView *_topicIcon;
    NSInteger _topicMessages;
    BOOL _topicMessagesKnown;
    /* the arcs of the stories of the person, round the picture of the bar; hidden while there are none */
    NoshiStoryRing *_storyRing;
    NoshiEmojiLabel *_title;
    NoshiStatusLabel *_subtitle;
    /* what the title view of the classic bar was made with, so it is made again only when one of these changes */
    NSString *_shownTitleKey;
    NoshiInputBar *_input;
    NoshiInputPanel *_panel;
    UILabel *_status;
    UIButton *_retry;

    /* what the server said, by message id, and what only this screen knows yet */
    NSMutableDictionary *_server;
    NSMutableArray *_local;
    NSMutableDictionary *_people;
    /* the messages whose sender is not known yet and was asked for, so each is asked for once */
    NSMutableSet *_senderLookups;
    NSDictionary *_senderRoles;
    NSArray *_items;
    NSMutableDictionary *_itemCache;
    NSCache *_replyCache;
    BOOL _loadingReplies;
    BOOL _openingComments;
    NSUInteger _replyGeneration;
    NSUInteger _themeRevision;
    int32_t _historyOldestId;
    /* the ids the store page held the last time it arrived, so what it stops holding can be told from what it never held */
    NSMutableSet *_storeIds;
    NSMutableSet *_confirmingGone;
    NSMutableSet *_sharingBusy;
    int32_t _sharingPeriod;
    int64_t _sharingOffsetMilliseconds;
    BOOL _canLoadMore;
    BOOL _loadingOlder;
    /* a page of older history arrived while the list was moving, and waits for it to stop */
    BOOL _olderDeferred;
    noshi_scroll_state _scroll;
    BOOL _scrollTargetKnown;
    CGFloat _scrollTargetOffset;
    CGFloat _preparedOffset;
    BOOL _scrollReadPending;
    BOOL _interacting;
    BOOL _updatingItems;
    BOOL _layingOutChat;
    BOOL _followingBottom;
    BOOL _livePending;
    /* how long the last rebuild of the rows took and when it ended, so a busy chat is rebuilt no more often than the main thread can afford */
    CFTimeInterval _rebuildCost;
    CFTimeInterval _rebuildEndedAt;
    /* the list shows a stretch of old history opened around a message, so its end is not the newest message of the chat */
    BOOL _window;
    BOOL _loadingWindow;
    BOOL _loadingNewer;
    BOOL _canLoadNewer;
    BOOL _rebuildNow;
    NSUInteger _windowToken;
    CADisplayLink *_liveLink;
    CADisplayLink *_followLink;
    /* the quick scroll to a message that was asked for (a reply, a search result, a pinned message, a bookmark): its own frame clock, so the rows load as it moves */
    CADisplayLink *_jumpLink;
    CFTimeInterval _jumpBegan;
    CFTimeInterval _jumpLength;
    CGFloat _jumpFrom;
    CGFloat _jumpTo;
    int32_t _jumpMessageId;
    CFTimeInterval _followTime;
    CFTimeInterval _followBegan;
    BOOL _loadedFirst;
    /* what the chat had read when it was opened, or -1 when it had nothing unread: the line of unread messages stays where it was while they are read */
    int32_t _unreadAnchor;
    /* the effects a message of this private chat can go with, and the one the message being sent takes */
    NSArray *_messageEffects;
    long long _nextSendEffect;
    BOOL _openUnread;
    BOOL _loading;
    int32_t _markedRead;
    NSMutableSet *_readMentionIds;
    /* ids of the one-time messages opened on this phone, which read as expired at once, before the server's edit of the message comes */
    NSMutableSet *_openedOnce;
    /* the "1" chip of the input bar as it stood when the recording that is being finished ended */
    BOOL _recordingOneTime;
    /* the one-time voice note that plays now: the track, the message, and whether the server was told yet */
    NoshiMedia *_onceVoice;
    int32_t _onceVoiceId;
    BOOL _onceVoiceOpened;
    BOOL _stickToBottom;
    BOOL _restoringScroll;
    /* the kept place is looked up once, when the chat opens: the end of a window loads the newest page again, and finding it there put the list back where it was left */
    BOOL _scrollRestoreChecked;
    /* the chat is still settling on its newest message: the kept page and the first fresh page land without a scroll animation, so the list never visibly travels */
    BOOL _opening;
    BOOL _panelShown;
    CGFloat _keyboardOverlap;
    CGFloat _laidOutWidth;
    BOOL _observing;
    BOOL _visible;
    BOOL _pollingReactions;
    BOOL _pollingPolls;
    NSMutableSet *_votingPolls;
    NSTimer *_reactionTimer;
    /* the first and last row on screen when the stickers were last given their turn to run, -2 before the first time */
    NSInteger _animatedFirst;
    NSInteger _animatedLast;
    NoshiReactionPicker *_reactionPicker;
    int32_t _reactionMessageId;
    /* the full list of reactions was opened from the menu of the message, which a tap outside the list brings back */
    BOOL _reactionPickerFromMenu;
    NSUInteger _reactionPickerToken;
    NSMutableSet *_reactionSending;
    NoshiVoiceRecorder *_voice;
    NoshiRoundRecorder *_roundRecorder;
    /* the phone is watched for the ear, and a voice message is being recorded because it came there */
    BOOL _raiseWatching;
    BOOL _raiseRecording;
    UIView *_roundPreview;
    /* the side of the circle that is on screen: the usual one, or less where the keyboard leaves no room above the input bar */
    CGFloat _roundSide;
    UIButton *_roundTorch;
    BOOL _roundTorchBusy;
    UILabel *_roundZoomLabel;
    CGFloat _roundZoomStart;
    BOOL _roundFlipping;
    UIView *_roundShade;
    NoshiRoundGlow *_roundGlow;
    /* the flash the person asked for: the torch on the back camera, the screen light on the front one */
    BOOL _roundFlash;
    NSTimer *_recordTimer;
    NoshiAttachFlow *_attach;
    NoshiFullChannel *_channelFull;
    UIControl *_pinnedBar;
    /* the bar is on its way out: it still draws, and the layout already gives it no height */
    BOOL _pinnedBarCollapsing;
    UIControl *_voiceBar;
    UILabel *_voiceTitle, *_voiceInfo, *_voiceJoin;
    NoshiVoiceChat *_voiceChat;
    NSUInteger _voiceToken;
    UILabel *_pinnedTitle;
    NoshiEmojiLabel *_pinnedText;
    int32_t _pinnedId;
    NoshiMessage *_commentsPost;
    NSUInteger _topicPinnedGeneration;
    int32_t _scrollTarget;
    int _scrollPages;
    UILabel *_toast;
    UIButton *_toEnd;
    /* the heart over the way down: the messages that got a reaction not seen yet, oldest last, and the count on its corner */
    UIButton *_reactionJump;
    UILabel *_reactionBadge;
    NSMutableArray *_unreadReactionIds;
    /* a pending message left the list because its copy from the server is in it, which the next change of rows must not play as a deletion */
    BOOL _localReplaced;
    NSUInteger _ghostReactionIndex;
    NoshiNextChatHint *_nextHint;
    NoshiDialog *_nextDialog;
    BOOL _toEndShown;
    UIButton *_menuButton;
    NoshiGreetingView *_greeting;
    NoshiPremiumGateView *_premiumGate;
    BOOL _greetingAsked;
    BOOL _paidBusy;
    BOOL _joinPending;
    /* the account has blocked this user: a button that lets them back in stands where the field is */
    BOOL _userBlocked;
    BOOL _membershipAsked;
    BOOL _joining;
    NoshiComposeContext *_context;
    /* the bubble with the three dots at the end of the chat while the other side types, and whether it stands there now */
    NoshiTypingBubble *_typingBubble;
    BOOL _typingShown;
    BOOL _typingSent;
    CFTimeInterval _typingSentAt;
    int32_t _replyToId;
    NSString *_replyQuote;
    int32_t _replyQuoteOffset;
    int32_t _editingId;
    /* the first frames of the videos sent from this screen, by the id the server gave them */
    NSMutableDictionary *_posters;
    int32_t _deleteId;
    BOOL _editBusy;
    NoshiSelectionBar *_selectionBar;
    NSMutableSet *_selectedIds;
    BOOL _selecting;
    BOOL _inputHiddenBeforeSelection;
    BOOL _pinnedList;
    NSInteger _pinnedCount;
    /* every message the chat has pinned, the newest first: the bar shows the one that belongs to the part of the history on screen */
    NSArray *_pinnedAll;
    UIImageView *_pinnedThumb;
    UIButton *_pinnedListButton;
    NoshiPinnedLine *_pinnedLine;
    NSUInteger _pinnedThumbToken;
    NoshiLinkRouter *_router;
    NoshiChatBots *_bots;
    NSString *_draftText;
    /* what the field held before a message was opened for editing, which the field gets back when the edit ends */
    NoshiDraft *_stashedDraft;
    /* the field was filled from the draft of the account, so what it holds now is the person's word and may be saved */
    BOOL _draftsActive;
    BOOL _applyingDraft;
    /* the keyboard is sliding, so the list and the field move together and nothing else may change the rows or the offset until it stops */
    BOOL _keyboardMoving;
    /* the message a draft answers while it is fetched, so a save in between keeps it */
    int32_t _pendingDraftReply;
    NSString *_startParam;
    NSString *_searchQuery;
    /* the search of the modern style, which stays on the chat itself: the bar over the header, the strip over the keyboard, and the matches newest first */
    NoshiChatSearchBar *_searchBar;
    NoshiChatSearchNav *_searchNav;
    NSArray *_searchHits;
    NSUInteger _searchPosition;
    NSUInteger _searchToken;
    NoshiPerson *_historyPerson;
    int32_t _startMessageId;
    NSArray *_menuReactions;
    BOOL _menuReactionsLoading;
    /* the chat takes any custom emoji as a reaction, not only the ones in _menuReactions */
    BOOL _menuCustomAllowed;
    /* the identities the account may write as in this supergroup, once the server listed more than itself */
    NSArray *_sendAsOptions;
    BOOL _sendAsRequested;
    BOOL _sendAsChanging;
    /* the identity the person picked on this screen, which outranks what the full channel said before the pick (that answer does not change) */
    NoshiSendAsOption *_sendAsPicked;
    NSMutableDictionary *_transcripts;
    NoshiVoiceTranscriber *_voiceJob;
    /* the reactors already asked for through the message of their reaction, so a user is asked for once per screen */
    NSMutableSet *_reactorLookups;
    /* the full users they came back as; a later history answer carries the min object again and must not take their photo away */
    NSMutableDictionary *_reactorPeople;
}
- (BOOL)codeCopyMessage:(int32_t)messageId stillMatches:(NSString *)source range:(NSRange)range style:(NoshiTextStyle)style;
@end

@implementation NoshiChatController

@synthesize closeHandler = _closeHandler;
@synthesize nextChatProvider = _nextChatProvider;
@synthesize pinnedList = _pinnedList;
@synthesize searchQuery = _searchQuery;
@synthesize historyPerson = _historyPerson;
@synthesize startMessageId = _startMessageId;
@synthesize draftText = _draftText;
@synthesize startParam = _startParam;

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _animatedFirst = _animatedLast = -2;
    _sharingPeriod = NOSHI_SHARING_PERIOD_DEFAULT;
    _session = [session retain];
    long long account = [NoshiSession accountIdInDirectory:session.directory];
    if (!dialog.saved && dialog.peerKind == 1 && account > 0 && dialog.peerId == account)
        _dialog = [[NoshiDialog savedMessagesOfUserId:account] retain];
    else
        _dialog = [dialog retain];
    dialog = _dialog;
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _server = [[NSMutableDictionary alloc] init];
    _local = [[NSMutableArray alloc] init];
    /* a message that failed while this chat was closed, or when it was left, is still the person's to send again or delete */
    [_local addObjectsFromArray:[session takeUnsentMessagesForDialog:dialog]];
    _people = [[NSMutableDictionary alloc] init];
    [_people setObject:[self chatAsPerson] forKey:[NSNumber numberWithLongLong:0]];
    _items = [[NSArray alloc] init];
    _itemCache = [[NSMutableDictionary alloc] init];
    _replyCache = [[NSCache alloc] init];
    _replyCache.countLimit = 200;
    _reactionSending = [[NSMutableSet alloc] init];
    _readMentionIds = [[NSMutableSet alloc] init];
    _openedOnce = [[NSMutableSet alloc] init];
    _stickToBottom = YES;
    _opening = YES;
    _unreadAnchor = dialog.unreadCount > 0 ? dialog.readInboxMaxId : -1;
    /* every chat opens on the first message the account has not read, not on the newest one: a chat with a person or a bot was left out, and a long unread run opened at its end */
    _openUnread = dialog.unreadCount > 0 && dialog.readInboxMaxId >= 0 && dialog.readInboxMaxId < INT32_MAX;
    _router = [[NoshiLinkRouter alloc] initWithSession:session avatars:avatars media:media stickers:stickers];
    _router.anchor = self;
    _bots = [[NoshiChatBots alloc] initWithSession:session dialog:dialog router:_router media:media host:self];
    return self;
}

- (void)dealloc {
    [_messageEffects release];
    [_commentsPost release];
    [[NoshiRoundPlayback sharedPlayback] forgetChain:self];
    for (NoshiMessage *message in _local) {
        NoshiOutgoing *sent = message.pendingSend;
        if (message.state == NoshiMessageStateSent && sent && sent->temporary && sent->path)
            [[NSFileManager defaultManager] removeItemAtPath:sent->path error:NULL];
        if (message.state == NoshiMessageStateFailed) [_session keepUnsentMessage:message forDialog:_dialog];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sharingExpiryReached) object:nil];
    [self stopFollowingBottom];
    [_liveLink invalidate];
    [_liveLink release];
    _document.delegate = nil;
    [_document release];
    _router.anchor = nil;
    _bots.host = nil;
    [_bots teardown];
    [_bots release];
    [_router release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runChatSearch:) object:nil];
    [_searchBar release];
    [_searchNav release];
    [_searchHits release];
    [_searchQuery release];
    [_historyPerson release];
    [_voiceJob cancel];
    [_voiceJob release];
    [_transcripts release];
    [_reactorLookups release];
    [_reactorPeople release];
    [_menuReactions release];
    [_sendAsOptions release];
    [_sendAsPicked release];
    [_votingPolls release];
    [_draftText release];
    [_stashedDraft release];
    [_typingBubble release];
    [_replyQuote release];
    [_startParam release];
    [_attach cancel];
    [_attach release];
    [self stopRaiseToSpeak];
    [self discardRecording];
    [_reactionTimer invalidate];
    [_reactionTimer release];
    [_reactionPicker release];
    [NoshiReactionEffect dismiss];
    [_reactionPromo setDismissHandler:nil];
    [_reactionPromo dismiss];
    [_reactionPromo release];
    [_reactionSending release];
    [_weak clear];
    [_weak release];
    [_session stopWatchingForOwner:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    /* the delegate of a cell is not retained, and the table can outlive this controller (a pop that is still on screen), so a round
       message that ends or a tap that lands after this point would reach whatever took the memory of the controller */
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiMessageCell class]]) ((NoshiMessageCell *)cell).delegate = nil;
    }
    _table.delegate = nil;
    _table.dataSource = nil;
    _input.delegate = nil;
    _panel.delegate = nil;
    [_closeHandler release];
    [_nextChatProvider release];
    [_nextHint release];
    [_nextDialog release];
    [_storeIds release];
    [_session release];
    [_dialog release];
    [_avatars release];
    [_media release];
    [_stickers release];
    _miniPlayer.changeHandler = nil;
    [_miniPlayer release];
    [_toEnd release];
    [_reactionJump release];
    [_reactionBadge release];
    [_unreadReactionIds release];
    [_wallpaper release];
    [_channelWallpaperSignature release];
    [_table release];
    [_header release];
    [_headerLine release];
    [_back release];
    [_backBadge release];
    [_avatar release];
    [_topicIcon release];
    [_storyRing release];
    [_title release];
    [_subtitle release];
    [_shownTitleKey release];
    [_input release];
    [_panel release];
    [_status release];
    [_channelFull release];
    [_context release];
    [_selectionBar release];
    [_selectedIds release];
    [_pinnedBar release];
    [_voiceBar release];
    [_voiceTitle release];
    [_voiceInfo release];
    [_voiceJoin release];
    [_voiceChat release];
    [_pinnedTitle release];
    [_pinnedText release];
    [_confirmingGone release];
    [_sharingBusy release];
    [_toast release];
    [_menuButton release];
    [_greeting release];
    [_premiumGate release];
    [_pinnedAll release];
    [_pinnedThumb release];
    [_pinnedListButton release];
    [_pinnedLine release];
    [_retry release];
    [_server release];
    [_local release];
    [_posters release];
    [_people release];
    [_senderLookups release];
    [_selfPerson release];
    [_accountId release];
    [_senderRoles release];
    [_items release];
    [_replyCache release];
    [_readMentionIds release];
    [_openedOnce release];
    [_onceVoice release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markVisibleMentionsRead) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadReplyPreviews) object:nil];
    [_itemCache release];
    [super dealloc];
}

#pragma mark views

static UILabel *NoshiChatLabel(UIColor *color, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

/* what the other side is doing in the chat, in words, or nil when nothing */
- (NSString *)typingText {
    if (_dialog.saved || _pinnedList) return nil;
    NSUInteger count = [_session.typing countInDialog:_dialog];
    int action = [_session.typing actionInDialog:_dialog];
    /* a private chat is the person itself; a group names who writes */
    if (_dialog.peerKind == 1) return NoshiTypingStatusText(action, count);
    return NoshiTypingStatusTextNamed(action, count, [_session.typing namesInDialog:_dialog]);
}

- (NoshiStatusKind)statusKind {
    if (_dialog.peerKind == 1 && _dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID) return NoshiStatusPlain;
    if ([self typingText]) return NoshiStatusTyping;
    if (!_session.connected) return NoshiStatusPlain;
    return _dialog.kind == NOSHI_DIALOG_USER && !_dialog.saved && _dialog.presence == NOSHI_PRESENCE_ONLINE ? NoshiStatusOnline : NoshiStatusPlain;
}

/* a topic of a forum: its dialog is built with the forum flag cleared and a topic id, and the comments of a post carry the discussion flag on top of that */
- (BOOL)isForumTopic {
    return _dialog.topicId > 0 && !_dialog.discussion && !_dialog.saved && !_pinnedList;
}

- (void)loadTopicMessageCount {
    if (![self isForumTopic]) return;
    NoshiWeakReference *weak = _weak;
    [_session loadMessageCountOfDialog:_dialog completion:^(NSInteger count, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: the messages of topic %d were not counted: %@", (int)chat->_dialog.topicId, errorName);
            return;
        }
        chat->_topicMessages = count;
        chat->_topicMessagesKnown = YES;
        [chat refreshStatusLine];
    }];
}

/* the icon is the custom emoji of the topic once its picture is in memory, the colored hash until then */
- (void)loadTopicIcon {
    if (![self isForumTopic] || !_topicIcon) return;
    _topicIcon.image = NoshiTopicIconImage(_dialog);
    if (!_dialog.topicIconEmoji) return;
    NoshiWeakReference *weak = _weak;
    [NoshiCustomEmojiLoader loadDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:_dialog.topicIconEmoji]] session:_session media:_media documents:nil picture:^{
        NoshiChatController *chat = weak.target;
        if (chat && chat->_topicIcon) chat->_topicIcon.image = NoshiTopicIconImage(chat->_dialog);
    }];
}

- (NSString *)statusLine {
    if (_dialog.peerKind == 1 && _dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID) return NSLocalizedString(@"chat.status.telegram", nil);
    NSString *typing = [self typingText];
    if (typing) return typing;
    /* a last seen time read off a dead link is stale, so the original client shows the connecting state instead */
    if (!_session.connected) return NoshiConnectingText(3);
    /* a topic counts its own messages, which the bar shows where a group shows its members */
    if ([self isForumTopic]) {
        if (!_topicMessagesKnown) return @"";
        return [NSString stringWithFormat:NSLocalizedString([@"topic.messages." stringByAppendingString:NoshiPluralForm(_topicMessages)], nil), (long)_topicMessages];
    }
    /* a channel or a group says how many follow it once the full channel is in; until then it names its kind */
    if (_channelFull.participants > 0 && (_dialog.kind == NOSHI_DIALOG_CHANNEL || _dialog.kind == NOSHI_DIALOG_GROUP)) {
        NSString *noun = _dialog.kind == NOSHI_DIALOG_CHANNEL ? @"chat.subscribers." : @"chat.members.";
        return [NSString stringWithFormat:NSLocalizedString([noun stringByAppendingString:NoshiPluralForm(_channelFull.participants)], nil), (long)_channelFull.participants];
    }
    switch (_dialog.kind) {
    case NOSHI_DIALOG_USER: return _dialog.saved ? @"" : NoshiLastSeenText(_dialog.presence, _dialog.seen);
    /* the replies are a service chat, not a bot anyone talks to */
    case NOSHI_DIALOG_BOT: return _dialog.replies ? @"" : NSLocalizedString(@"chat.status.bot", nil);
    case NOSHI_DIALOG_GROUP: return NSLocalizedString(@"chat.status.group", nil);
    case NOSHI_DIALOG_CHANNEL: return NSLocalizedString(@"chat.status.channel", nil);
    }
    return @"";
}

/* the status line follows the typing of this chat only */
- (void)typingChanged:(NSNotification *)note {
    if (!NoshiTypingChangeConcerns(note, _dialog)) return;
    [self refreshStatusLine];
    if ([self typingBubbleWanted] != _typingShown) {
        [self layoutChat];
    }
}

/* the height the bubble takes at the foot of the list, with its gap */
/* the room under the last message that the three dots take, with the gap above them: the dots stood three points from the message and read as part of it; the footer grows by the six
   points the gap gained, so the room under the dots stays what it was */
#define TYPING_GAP 9.0
#define TYPING_SPACE 42.0

/* a window around an old message, a list of pins and the notes to oneself have no end that the other side writes at */
- (BOOL)typingBubbleWanted {
    return !_pinnedList && !_dialog.saved && !_window && _loadedFirst && _dialog.kind != NOSHI_DIALOG_CHANNEL && [self typingText] != nil;
}

- (void)placeTypingBubble {
    BOOL want = [self typingBubbleWanted];
    if (want) {
        if (!_typingBubble) {
            _typingBubble = [[NoshiTypingBubble alloc] initWithFrame:CGRectZero];
            _typingBubble.hidden = YES;
        }
        UIView *footer = _table.tableFooterView;
        if (!footer) {
            footer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, _table.bounds.size.width, TYPING_SPACE)] autorelease];
            footer.backgroundColor = [UIColor clearColor];
            [footer addSubview:_typingBubble];
            _table.tableFooterView = footer;
        }
        CGSize bubbleSize = [NoshiTypingBubble size];
        _typingBubble.bounds = CGRectMake(0, 0, bubbleSize.width, bubbleSize.height);
        _typingBubble.center = CGPointMake(10 + bubbleSize.width / 2, TYPING_GAP + bubbleSize.height / 2);
        [_typingBubble applyTheme];
        if (!_typingShown) {
            _typingShown = YES;
            _typingBubble.hidden = NO;
            _typingBubble.transform = CGAffineTransformIdentity;
            /* it comes up from below and grows a little, as a message that arrives does in the intro of the app */
            _typingBubble.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.88f, 0.88f), CGAffineTransformMakeTranslation(0, 26));
            _typingBubble.alpha = 0;
            NoshiAnimateView(_typingBubble, CGAffineTransformIdentity, 1, NOSHI_MOTION_ENTER, nil);
            [_typingBubble startBeat];
        }
    } else if (_typingShown) {
        _typingShown = NO;
        _typingBubble.hidden = YES;
        _table.tableFooterView = nil;
    }
}

- (void)refreshStatusLine {
    if (_pinnedList) return;
    NSString *line = [self statusLine];
    if (_subtitle) {
        [_subtitle setStatus:line kind:[self statusKind]];
        [self.view setNeedsLayout];
    } else if ([self isViewLoaded]) {
        (void)line;
        [self installClassicTitleView];
    }
}

/* the name and the status in the classic bar, as wide as the bar leaves beside the back arrow and its count */
- (void)installClassicTitleView {
    /* the screen asks again each time it appears, and a new view in the middle of the slide back from a profile was laid out at the left edge and jumped to the middle when
       the slide ended; the same words and width keep the view that is there */
    NSString *status = [self statusLine];
    CGFloat width = [self classicTitleWidth];
    NSString *key = [NSString stringWithFormat:@"%@\n%@\n%d\n%.1f", _dialog.title, status, (int)[self statusKind], width];
    if (self.navigationItem.titleView && [key isEqualToString:_shownTitleKey]) return;
    [_shownTitleKey release];
    _shownTitleKey = [key copy];
    self.navigationItem.titleView = NoshiClassicTitleViewWithStatusWidth(_dialog.title, status, (int)[self statusKind], width);
    self.navigationItem.titleView.userInteractionEnabled = YES;
    [self.navigationItem.titleView addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _wallpaper = [[UIImageView alloc] init];
    NoshiApplyChatWallpaperForChat(_wallpaper, NoshiThemeIsDark(), _dialog.peerKind, _dialog.peerId);
    [root addSubview:_wallpaper];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wallpaperDidChange) name:NoshiWallpaperDidChangeNotification object:nil];
    /* the song that plays follows the person into the chat, with the buttons to change it; the strip has no height while nothing plays */
    _miniPlayer = [[NoshiMiniPlayer alloc] init];
    _miniPlayer.pill = YES;
    NoshiWeakReference *playerWeak = _weak;
    _miniPlayer.changeHandler = ^{
        NoshiChatController *chat = playerWeak.target;
        [chat relayoutAnimatedThen:nil];
    };
    [root addSubview:_miniPlayer];
    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
    NoshiScrollViewOwnsInsets(_table);
    NoshiTableUsesExactHeights(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.allowsSelection = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.hidden = YES;
    [root addSubview:_table];
    /* the pill is translucent and the list runs under it, so it has to stand above the list */
    [root insertSubview:_miniPlayer aboveSubview:_table];
    /* a tap on the list puts the keyboard or the panel away, or brings the keyboard back while a message is edited from the panel */
    UITapGestureRecognizer *dismiss = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(listTapped)] autorelease];
    dismiss.cancelsTouchesInView = NO;
    [_table addGestureRecognizer:dismiss];

    _status = NoshiChatLabel(NoshiColorSecondary(), NoshiTextAlignmentCenter);
    _status.numberOfLines = 0;
    _status.hidden = YES;
    [root addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(loadNewest) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];

    _input = [[NoshiInputBar alloc] init];
    _input.session = _session;
    _input.media = _media;
    _input.formatHost = root;
    _joinPending = _dialog.peerKind == 3 && _dialog.left && !_pinnedList && [self membershipRequired];
    if (_joinPending) _input.actionTitle = NSLocalizedString(@"chat.join", nil);
    _input.delegate = self;
    if (_dialog.kind == NOSHI_DIALOG_CHANNEL && !_dialog.canPost) {
        _input.writable = NO;
        _input.readOnlyNote = NSLocalizedString(@"chat.readonly", nil);
    } else if (_dialog.deleted && _dialog.peerKind == 1) {
        /* a deleted account takes no messages: the server refuses them, and the one sent here stayed in the chat as failed */
        _input.writable = NO;
        _input.readOnlyNote = NSLocalizedString(@"chat.deleted.readonly", nil);
    } else if (_dialog.replies) {
        /* nobody writes to the chat of the replies; it is read, like a channel */
        _input.writable = NO;
        _input.readOnlyNote = NSLocalizedString(@"chat.replies.readonly", nil);
    } else if (_dialog.savedSource && !_dialog.savedSource.saved) {
        /* a message written here would be the account's own note, not one from the chat the list is narrowed to */
        _input.writable = NO;
        _input.readOnlyNote = NSLocalizedString(@"chat.saved.readonly", nil);
    }
    [self applySendBanOfDialog:_dialog];
    [self applyClosedTopic];
    [root addSubview:_input];
    _context = [[NoshiComposeContext alloc] init];
    _context.hidden = YES;
    NoshiWeakReference *contextWeak = _weak;
    _context.closeHandler = ^{ [(NoshiChatController *)contextWeak.target cancelCompose]; };
    [root addSubview:_context];
    _selectionBar = [[NoshiSelectionBar alloc] init];
    _selectionBar.hidden = YES;
    NoshiWeakReference *barWeak = _weak;
    _selectionBar.cancelHandler = ^{ [(NoshiChatController *)barWeak.target endSelection]; };
    _selectionBar.forwardHandler = ^{ [(NoshiChatController *)barWeak.target forwardSelected]; };
    _selectionBar.copyHandler = ^{ [(NoshiChatController *)barWeak.target copySelected]; };
    _selectionBar.deleteHandler = ^{ [(NoshiChatController *)barWeak.target askDeleteSelected]; };
    _selectionBar.rangeHandler = ^{ [(NoshiChatController *)barWeak.target selectBetween]; };
    [root addSubview:_selectionBar];
    /* the pinned message of a channel stands under the header, over the list */
    _pinnedBar = [[UIControl alloc] init];
    _pinnedBar.backgroundColor = NoshiColorBar();
    _pinnedBar.clipsToBounds = YES;
    /* the same plain ground as the strip of the player, black on the dark theme and white on the light one: the wallpaper showed through the bar, and the purple plate made a stripe */
    _pinnedBar.backgroundColor = NoshiClassicStripGround();
    _pinnedBar.hidden = YES;
    [_pinnedBar addTarget:self action:@selector(pinnedTapped) forControlEvents:UIControlEventTouchUpInside];
    _pinnedLine = [[NoshiPinnedLine alloc] initWithFrame:CGRectMake(12, 0, 2, PINNED_HEIGHT)];
    [_pinnedBar addSubview:_pinnedLine];
    _pinnedTitle = NoshiChatLabel(NoshiThemeIsDark() ? [UIColor colorWithRed:0.82 green:0.94 blue:1 alpha:1] : NoshiColorAccent(), NoshiTextAlignmentLeft);
    _pinnedTitle.text = NSLocalizedString(@"chat.pinned", nil);
    _pinnedTitle.userInteractionEnabled = NO;
    [_pinnedBar addSubview:_pinnedTitle];
    /* the pinned message is somebody's text, so its emoji come from the app's pictures */
    _pinnedText = [[NoshiEmojiLabel alloc] init];
    _pinnedText.textColor = NoshiClassicStripInk();
    _pinnedText.userInteractionEnabled = NO;
    [_pinnedBar addSubview:_pinnedText];
    /* a photo or video shows as a small rounded square at the left, and a chat with several pinned messages gets the list button */
    _pinnedThumb = [[UIImageView alloc] init];
    _pinnedThumb.contentMode = UIViewContentModeScaleAspectFill;
    _pinnedThumb.clipsToBounds = YES;
    _pinnedThumb.layer.cornerRadius = 6;
    _pinnedThumb.hidden = YES;
    _pinnedThumb.userInteractionEnabled = NO;
    [_pinnedBar addSubview:_pinnedThumb];
    _pinnedListButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_pinnedListButton setImage:NoshiSymbolImage(NoshiSymbolPinnedList, 22, NoshiClassicStripInk()) forState:UIControlStateNormal];
    [_pinnedListButton addTarget:self action:@selector(openPinnedList) forControlEvents:UIControlEventTouchUpInside];
    _pinnedListButton.accessibilityLabel = NSLocalizedString(@"chat.pinned.all", nil);
    _pinnedListButton.hidden = YES;
    [_pinnedBar addSubview:_pinnedListButton];
    UIView *foot = [[[UIView alloc] init] autorelease];
    foot.backgroundColor = NoshiClassicStripEdge();
    foot.userInteractionEnabled = NO;
    foot.tag = PINNED_FOOT_TAG;
    [_pinnedBar addSubview:foot];
    [root addSubview:_pinnedBar];
    /* the voice chat that runs in a group or channel: a bar under the pinned message with who is in it and the way to join */
    _voiceBar = [[UIControl alloc] init];
    _voiceBar.backgroundColor = NoshiColorBar();
    _voiceBar.hidden = YES;
    [_voiceBar addTarget:self action:@selector(openVoiceChat) forControlEvents:UIControlEventTouchUpInside];
    _voiceTitle = NoshiChatLabel(NoshiColorTitle(), NoshiTextAlignmentLeft);
    _voiceTitle.text = NSLocalizedString(@"chat.voice.title", nil);
    _voiceTitle.userInteractionEnabled = NO;
    [_voiceBar addSubview:_voiceTitle];
    _voiceInfo = NoshiChatLabel(NoshiColorSecondary(), NoshiTextAlignmentLeft);
    _voiceInfo.userInteractionEnabled = NO;
    [_voiceBar addSubview:_voiceInfo];
    _voiceJoin = NoshiChatLabel([UIColor whiteColor], NoshiTextAlignmentCenter);
    _voiceJoin.backgroundColor = NoshiColorAccent();
    _voiceJoin.layer.cornerRadius = 14;
    _voiceJoin.layer.masksToBounds = YES;
    _voiceJoin.text = NSLocalizedString(@"chat.voice.join", nil);
    _voiceJoin.userInteractionEnabled = NO;
    [_voiceBar addSubview:_voiceJoin];
    [root addSubview:_voiceBar];
    _toast = NoshiChatLabel([UIColor whiteColor], NoshiTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
    /* the way back to the newest message, which shows once the list is more than a screen above its end */
    _toEnd = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    /* the same round key as the send button of the bar */
    [_toEnd setImage:NoshiFlatDownButtonImage(44, NO) forState:UIControlStateNormal];
    [_toEnd setImage:NoshiFlatDownButtonImage(44, YES) forState:UIControlStateHighlighted];
    [_toEnd addTarget:self action:@selector(toEndTapped) forControlEvents:UIControlEventTouchUpInside];
    _toEnd.accessibilityLabel = NSLocalizedString(@"chat.toend", nil);
    _toEnd.alpha = 0;
    _toEnd.hidden = YES;
    [root addSubview:_toEnd];
    _reactionJump = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _reactionJump.layer.cornerRadius = 22;
    [_reactionJump setBackgroundImage:NoshiClassicRedRoundButtonImage(NoshiSymbolHeart, 44, NO) forState:UIControlStateNormal];
    [_reactionJump setBackgroundImage:NoshiClassicRedRoundButtonImage(NoshiSymbolHeart, 44, YES) forState:UIControlStateHighlighted];
    [_reactionJump addTarget:self action:@selector(reactionJumpTapped) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *reactionHold = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(reactionJumpHeld:)] autorelease];
    [_reactionJump addGestureRecognizer:reactionHold];
    _reactionJump.accessibilityLabel = NSLocalizedString(@"chat.reactions.jump", nil);
    _reactionJump.hidden = YES;
    [root addSubview:_reactionJump];
    _reactionBadge = [[UILabel alloc] init];
    _reactionBadge.font = NoshiFontSemibold(12);
    _reactionBadge.textColor = [UIColor whiteColor];
    _reactionBadge.textAlignment = NoshiTextAlignmentCenter;
    _reactionBadge.backgroundColor = [UIColor colorWithRed:0.20 green:0.50 blue:0.92 alpha:1];
    _reactionBadge.layer.cornerRadius = 11;
    _reactionBadge.layer.masksToBounds = YES;
    _reactionBadge.userInteractionEnabled = NO;
    _reactionBadge.hidden = YES;
    [root addSubview:_reactionBadge];
    [self loadUnreadReactions];
    _nextHint = [[NoshiNextChatHint alloc] init];
    /* the hint sits in the list at the end of its content, in the space a pull past the last message opens */
    [_table addSubview:_nextHint];

    if (_pinnedList) {
        self.title = NSLocalizedString(@"chat.pinned.list", nil);
        _input.hidden = YES;
        return;
    }
    /* the system's navigation bar carries the name and the status, the person's picture and the back button */
    _classicBack = !NoshiIsDetailRoot(self);
    if (_classicBack) {
        self.navigationItem.hidesBackButton = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(unreadTotalChanged:) name:NoshiUnreadTotalDidChangeNotification object:nil];
        /* the count is known before the title, so the title is made as wide as the room beside the arrow allows */
        [self refreshBackBadge];
    }
    [self installClassicTitleView];
    NoshiAvatarView *mini = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)] autorelease];
    mini.seed = _dialog.avatarSeed;
    mini.initials = _dialog.initials;
    mini.deleted = _dialog.deleted;
    mini.accent = _dialog.saved || _dialog.replies;
    mini.showsSymbol = _dialog.saved || _dialog.replies;
    mini.symbol = _dialog.replies ? NoshiSymbolReply : NoshiSymbolBookmark;
    [mini setPhoto:_dialog.saved || _dialog.replies ? nil : _dialog.photo cache:_avatars];
    mini.userInteractionEnabled = YES;
    [mini addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
    /* the ring stands in the bar item, which is a little wider than the picture, so the bar does not clip it */
    CGFloat outset = 3;
    UIView *avatarBox = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 32 + 2 * outset, 32 + 2 * outset)] autorelease];
    _storyRing = [[NoshiStoryRing alloc] initWithFrame:avatarBox.bounds];
    _storyRing.hidden = YES;
    [avatarBox addSubview:_storyRing];
    mini.frame = CGRectMake(outset, outset, 32, 32);
    if ([self isForumTopic]) {
        /* a topic wears its own icon, as in the modern bar, and not the initials of the group; loadTopicIcon swaps in the custom emoji once it is in memory */
        _topicIcon = [[UIImageView alloc] initWithFrame:mini.frame];
        _topicIcon.contentMode = UIViewContentModeScaleAspectFit;
        _topicIcon.userInteractionEnabled = YES;
        [_topicIcon addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
        [avatarBox addSubview:_topicIcon];
    } else [avatarBox addSubview:mini];
    UIBarButtonItem *avatarItem = [[[UIBarButtonItem alloc] initWithCustomView:avatarBox] autorelease];
    UIBarButtonItem *dotsItem = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(NoshiSymbolEllipsis, 22, [UIColor whiteColor])
                                                                   style:UIBarButtonItemStylePlain target:self action:@selector(showChatMenu)] autorelease];
    dotsItem.accessibilityLabel = NSLocalizedString(@"profile.more", nil);
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:dotsItem, avatarItem, nil];
}

- (void)chatTitleTapped:(UITapGestureRecognizer *)tap {
    [self openProfileGifts];
}

/* the ring round the picture follows the stories of the person: arcs coloured while unseen, grey once seen */
- (void)loadStories {
    if (_dialog.kind != NOSHI_DIALOG_USER || _dialog.saved || _pinnedList || !_storyRing) return;
    NoshiWeakReference *weak = _weak;
    [_session loadStoriesOfDialog:_dialog completion:^(NoshiStoryPeer *peer, NSArray *stories, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || errorName) return;
        chat->_storyRing.hidden = !stories.count;
        if (stories.count) [chat->_storyRing setPeer:peer];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(voicePlayerChanged:) name:NoshiMusicPlayerDidChangeNotification object:[NoshiMusicPlayer sharedPlayer]];
    [self loadStories];
    [self loadTopicIcon];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reactionArtworkLoaded) name:NoshiReactionArtworkDidLoadNotification object:nil];
    [NoshiReactionArtwork loadWithSession:_session media:_media];
    if (_dialog.peerKind == 1 && !_dialog.saved && !_pinnedList) {
        NoshiWeakReference *weak = _weak;
        [_session loadSharingPeriod:^(int32_t seconds, int64_t offset, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat) return;
            if (errorName) NSLog(@"noshigram: sharing request lifetime was not refreshed: %@", errorName);
            chat->_sharingPeriod = seconds;
            chat->_sharingOffsetMilliseconds = offset;
            [chat rebuildItems];
        }];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liteModeChanged) name:NoshiLiteModeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(readOutboxChanged:) name:NoshiReadOutboxDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userStatusChanged:) name:NoshiUserStatusDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timesChanged) name:NoshiTimeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadProgressed:) name:NoshiUploadProgressNotification object:_session];
    if (_dialog.saved) {
        NoshiWeakReference *weak = _weak;
        [self whenPremiumKnown:^(BOOL premium) {
            NoshiChatController *chat = weak.target;
            if (chat && premium) [chat rebuildItems];
        }];
    }
    if (_pinnedList) [self loadPinnedList];
    else [self loadNewest];
    [self loadMessageEffectsIfPrivate];
    if (_dialog.peerKind == 3) [self loadChannelFull];
    else if (!_pinnedList) [self loadTopicPinned];
    if (!_pinnedList) [self loadPremiumGate];
    [self loadBlockedState];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(peerBlockChanged:) name:NoshiPeerBlockDidChangeNotification object:nil];
    /* asked now, so the first menu already has its reaction pill and shows card and pill together */
    if (!_pinnedList && ![self reactionsHidden]) [self loadMenuReactionsThen:nil];
    if (_dialog.kind == NOSHI_DIALOG_GROUP) {
        NoshiWeakReference *weak = _weak;
        [_session loadSenderRolesOfDialog:_dialog completion:^(NSDictionary *roles, NSDictionary *people, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat) return;
            if (errorName) {
                NSLog(@"noshigram: group sender roles did not load: %@", errorName);
                return;
            }
            [chat->_senderRoles release];
            chat->_senderRoles = [roles copy];
            [chat->_people addEntriesFromDictionary:people];
            [chat rebuildItems];
        }];
    }
    _bots.startParam = _startParam;
    if (!_pinnedList) [_bots start];
    if (_draftText.length) [self applyDraft:_draftText];
    else [self restoreDraft];
    _draftsActive = !_pinnedList && !_dialog.savedSource;
    if (_draftsActive) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftBoardChanged:) name:NoshiDraftDidChangeNotification object:_session.drafts];
}

#pragma mark bots

- (void)applyDraft:(NSString *)text {
    if (!text.length || !_input) return;
    _input.textView.text = text;
    [_input.textView.delegate textViewDidChange:_input.textView];
    [_input.textView becomeFirstResponder];
}

- (NoshiInputBar *)botsInputBar { return _input; }
- (UIView *)botsContainerView { return self.view; }
- (long long)botsRandomId { return [self newRandomId]; }
- (CGFloat)botsKeyboardMaxHeight { return [self panelHeight]; }
- (void)botsSetDraft:(NSString *)text { [self applyDraft:text]; }
- (void)botsSendText:(NSString *)text replyTo:(int32_t)replyTo { [self sendText:text entities:nil replyTo:replyTo]; }
- (int32_t)botsInlineReplyId { return _replyToId; }
- (void)botsInlineDidSendReply:(int32_t)replyId { if (replyId && _replyToId == replyId) [self cancelCompose]; }
- (BOOL)botsCanSendInline { return !_editingId && _input.writable; }

- (void)botsRelayout {
    if (!self.isViewLoaded) return;
    [self relayoutAnimatedThen:nil];
}

/* the people the history named, without the account itself */
- (NSArray *)botsMentionCandidates {
    long long mine = [NoshiSession accountIdInDirectory:_session.directory];
    NSMutableArray *people = [NSMutableArray arrayWithCapacity:_people.count];
    for (id key in _people) {
        NoshiPerson *person = [_people objectForKey:key];
        if ([person isKindOfClass:[NoshiPerson class]] && person.userId > 0 && person.userId != mine) [people addObject:person];
    }
    return people;
}

- (NoshiPerson *)botsPersonForUserId:(long long)userId {
    return [_people objectForKey:[NSNumber numberWithLongLong:userId]];
}

/* a bot's keyboard stands in for the system keyboard, as the emoji panel does, and the two give way to each other */
- (void)botsSetInputView:(UIView *)view {
    UITextView *text = _input.textView;
    if (view && _panelShown) {
        _panelShown = NO;
        _input.panelShown = NO;
    }
    text.inputView = view;
    if (view && ![text isFirstResponder]) [text becomeFirstResponder];
    else if ([text isFirstResponder]) [text reloadInputViews];
}

- (void)botsRequestLocation {
    [[self attachFlow] chooseLocation];
}

- (NoshiAttachFlow *)attachFlow {
    if (_attach.cancelled) { [_attach release]; _attach = nil; }
    if (!_attach) {
        NoshiWeakReference *weak = _weak;
        _attach = [[NoshiAttachFlow alloc] initWithHost:self handler:^(NoshiOutgoing *outgoing) {
            NoshiChatController *chat = weak.target;
            if (chat) [chat sendOutgoing:outgoing];
        }];
        _attach.session=_session;
        _attach.dialog=_dialog;
        _attach.albumHandler = ^(NSArray *outgoings) {
            NoshiChatController *chat = weak.target;
            if (chat) [chat sendAlbum:outgoings];
        };
    }
    return _attach;
}

/* a blocked person cannot be written to, and the field gives way to the button that lets them back in, as in the official clients */
- (void)loadBlockedState {
    if (_dialog.kind != NOSHI_DIALOG_USER || _dialog.saved || _pinnedList) return;
    NoshiWeakReference *weak = _weak;
    [_session loadFullUserOfDialog:_dialog completion:^(NoshiFullUser *user, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || !user) {
            if (errorName) NSLog(@"noshigram: the block state did not load: %@", errorName);
            return;
        }
        [chat setUserBlocked:user.blocked];
    }];
}

- (void)setUserBlocked:(BOOL)blocked {
    if (blocked == _userBlocked) return;
    _userBlocked = blocked;
    NSString *title = NSLocalizedString(@"chat.unblock", nil);
    if (blocked) {
        _input.actionTitle = title;
    } else if ([_input.actionTitle isEqualToString:title]) {
        _input.actionTitle = nil;
    }
    [self.view setNeedsLayout];
}

- (void)peerBlockChanged:(NSNotification *)note {
    NSNumber *peer = [note.userInfo objectForKey:@"peer"], *kind = [note.userInfo objectForKey:@"kind"];
    if (peer.longLongValue != _dialog.peerId || (kind && kind.intValue != _dialog.peerKind)) return;
    [self setUserBlocked:[[note.userInfo objectForKey:@"blocked"] boolValue]];
}

- (void)unblockUser {
    NoshiWeakReference *weak = _weak;
    [_session setBlocked:NO kind:_dialog.peerKind identifier:_dialog.peerId hash:_dialog.peerHash completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || !errorName) return;
        NSLog(@"noshigram: the unblock failed: %@", errorName);
        NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
    }];
}

- (void)inputBarDidTapMenu:(NoshiInputBar *)bar { (void)bar; [_bots menuTapped]; }
- (void)inputBarDidTapBotKeyboard:(NoshiInputBar *)bar { (void)bar; [_bots keyboardButtonTapped]; }
- (void)inputBarDidTapAction:(NoshiInputBar *)bar {
    (void)bar;
    if (_userBlocked) [self unblockUser];
    else if (_joinPending) [self joinChannel];
    else [_bots actionTapped];
}
- (void)inputBarDidChangeText:(NoshiInputBar *)bar {
    (void)bar;
    [_bots inputTextChanged];
    [self draftStateChanged];
    if (!_draftsActive || _applyingDraft || !_visible || !_input.textView.isFirstResponder || _dialog.saved || _dialog.kind == NOSHI_DIALOG_CHANNEL) return;
    BOOL typing = _input.textView.text.length > 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (!typing && !_typingSent) return;
    if (typing && _typingSent && now - _typingSentAt < 4.0) return;
    [_session setTyping:typing inDialog:_dialog];
    _typingSent = typing;
    _typingSentAt = now;
}

- (void)messageCell:(NoshiMessageCell *)cell didPressButton:(NoshiMarkupButton *)button {
    [_bots pressButton:button ofMessage:cell.item.message cell:cell];
}

#pragma mark pinned list

- (void)loadPinnedList {
    _loading = YES;
    [self stopFollowingBottom];
    _stickToBottom = NO;
    NoshiWeakReference *weak = _weak;
    NoshiHistoryCompletion loaded = ^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_loading = NO;
        /* a list of pinned or found messages has no newest message to settle on */
        chat->_opening = NO;
        if (!messages) {
            [chat showStatus:[chat failureTextForError:errorName] retry:YES];
            return;
        }
        chat->_loadedFirst = YES;
        chat->_table.hidden = NO;
        [chat->_people addEntriesFromDictionary:people];
        [chat mergeMessages:messages];
        chat->_canLoadMore = NO;
        NSString *title;
        if ([chat listIsFound]) {
            title = [chat listTitle];
        } else {
            NSString *form = [@"chat.pinned.count." stringByAppendingString:NoshiPluralForm((NSInteger)messages.count)];
            title = messages.count ? [NSString stringWithFormat:NSLocalizedString(form, nil), (long)messages.count] : NSLocalizedString(@"chat.pinned.list", nil);
        }
        if (chat->_title) {
            chat->_title.entities = nil;
            chat->_title.text = title;
        }
        else chat.title = title;
        if (!messages.count) [chat showStatus:NSLocalizedString([chat listIsFound] ? @"chat.search.none" : @"chat.pinned.none", nil) retry:NO];
        [chat rebuildItems];
    };
    if (_historyPerson) [_session searchMessagesOfDialog:_dialog fromUserId:_historyPerson.userId accessHash:_historyPerson.accessHash completion:loaded];
    else if (_searchQuery.length) [_session searchMessagesOfDialog:_dialog query:_searchQuery completion:loaded];
    else [_session loadPinnedMessagesOfDialog:_dialog completion:loaded];
}

/* the list is the answer to a search of some kind and not the pinned messages */
- (BOOL)listIsFound {
    return _searchQuery.length || _historyPerson;
}

/* the title of a list screen: what was searched for, whose messages these are, or the pinned ones */
- (NSString *)listTitle {
    if (_historyPerson) return [NSString stringWithFormat:NSLocalizedString(@"chat.history.title", nil), _historyPerson.name];
    if (_searchQuery.length) return [NSString stringWithFormat:NSLocalizedString(@"chat.search.title", nil), _searchQuery];
    return NSLocalizedString(@"chat.pinned.list", nil);
}

/* the list of every pinned message of the chat: this same screen, over only those messages */
- (void)openPinnedList {
    NoshiChatController *list = [[[NoshiChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    list.pinnedList = YES;
    [self.navigationController pushViewController:list animated:YES];
}

#pragma mark channel

#pragma mark send as

/* a supergroup lets the account write as itself or as a channel it administers, or anonymously as the group; the identities are asked for once the
   full channel is in, since it names the one the server keeps */
- (void)loadSendAsOptions {
    if (_sendAsRequested || _pinnedList || _dialog.peerKind != 3 || _dialog.kind != NOSHI_DIALOG_GROUP || NoshiChatFlagGet(NoshiChatFlagHideSendAs)) return;
    _sendAsRequested = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadSendAsOptionsOfDialog:_dialog completion:^(NSArray *options, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!options) {
            NSLog(@"noshigram: the identities to write as did not load: %@", errorName);
            chat->_sendAsRequested = NO;
            return;
        }
        [chat->_sendAsOptions release];
        chat->_sendAsOptions = [options retain];
        [chat refreshSendAs];
    }];
}

/* the identity in use: the one chosen on this phone, else the one the server keeps, else the account itself */
- (NoshiSendAsOption *)currentSendAsOption {
    if (_sendAsPicked) return _sendAsPicked;
    NoshiDialog *chosen = [_session sendAsIdentityOfDialog:_dialog];
    NoshiSendAsOption *account = nil;
    for (NoshiSendAsOption *option in _sendAsOptions) {
        if (option.isAccount) account = option;
        BOOL same = chosen ? (option.identity.peerKind == chosen.peerKind && option.identity.peerId == chosen.peerId)
                           : (_channelFull.sendAsId > 0 && option.identity.peerKind == _channelFull.sendAsKind && option.identity.peerId == _channelFull.sendAsId);
        if (same) return option;
    }
    return account;
}

- (void)refreshSendAs {
    if (_sendAsOptions.count < 2) {
        _input.senderVisible = NO;
        return;
    }
    NoshiSendAsOption *current = [self currentSendAsOption];
    if (!current) {
        _input.senderVisible = NO;
        return;
    }
    /* what the server keeps becomes what later messages carry */
    [_session adoptSendAsIdentity:current.identity ofDialog:_dialog];
    NoshiDialog *identity = current.identity;
    _input.senderAvatar.initials = identity.initials;
    _input.senderAvatar.seed = (NSUInteger)(identity.peerId % 1000003);
    [_input.senderAvatar setPhoto:identity.photo cache:_avatars];
    _input.senderVisible = YES;
    [self.view setNeedsLayout];
}

- (void)selectSendAsOption:(NoshiSendAsOption *)option {
    if (_sendAsChanging) return;
    _sendAsChanging = YES;
    NoshiWeakReference *weak = _weak;
    NoshiSendAsOption *before = [_sendAsPicked retain];
    [_sendAsPicked release]; _sendAsPicked = [option retain];
    [_session chooseSendAsIdentity:option.identity ofDialog:_dialog completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (chat) {
            chat->_sendAsChanging = NO;
            if (errorName) {
                NSLog(@"noshigram: the identity to write as was refused: %@", errorName);
                NSString *message = [errorName isEqualToString:@"SEND_AS_PEER_INVALID"] && option.premiumRequired && chat->_premiumKnown && !chat->_premium
                    ? NSLocalizedString(@"chat.sendas.premium", nil) : NoshiGiftErrorText(errorName);
                NoshiGiftAlert(nil, message);
                [chat->_sendAsPicked release]; chat->_sendAsPicked = [before retain];
            }
            [chat refreshSendAs];
        }
        [before release];
    }];
    [self refreshSendAs];
}

- (void)inputBarDidTapSender:(NoshiInputBar *)bar {
    (void)bar;
    if (_sendAsOptions.count < 2 || _sendAsChanging) return;
    [self dismissInput];
    NoshiWeakReference *weak = _weak;
    void (^pick)(NSUInteger) = ^(NSUInteger index) {
        NoshiChatController *chat = weak.target;
        if (!chat || index >= chat->_sendAsOptions.count) return;
        NoshiSendAsOption *option = [chat->_sendAsOptions objectAtIndex:index];
        if (!option.premiumRequired) { [chat selectSendAsOption:option]; return; }
        [chat whenPremiumKnown:^(BOOL premium) {
            NoshiChatController *again = weak.target;
            if (!again) return;
            if (!again->_premiumKnown) { NoshiGiftAlert(nil, NSLocalizedString(@"error.offline", nil)); return; }
            if (!premium) { NoshiGiftAlert(nil, NSLocalizedString(@"chat.sendas.premium", nil)); return; }
            [again selectSendAsOption:option];
        }];
    };
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:_sendAsOptions.count];
    for (NoshiSendAsOption *option in _sendAsOptions) [titles addObject:option.isAccount ? NSLocalizedString(@"chat.sendas.account", nil) : option.identity.title];
    [NoshiSheet presentInView:self.view title:NSLocalizedString(@"chat.sendas", nil) message:NSLocalizedString(@"chat.sendas.info", nil) options:titles destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:pick];
}

/* the way in stands where the field would be while the account is outside the channel */
/* the comments of a post are open to people who are not in the discussion group, unless the group asks its writers to join; every other chat asks a stranger to join */
- (BOOL)membershipRequired {
    return !_dialog.discussion || _dialog.joinToSend || _channelFull.dialog.joinToSend;
}

- (void)applyMembership:(BOOL)member {
    if (_joining) return;
    _joinPending = !member && !_pinnedList && [self membershipRequired];
    if (_joinPending) {
        [_input.textView resignFirstResponder];
        [self stopRaiseToSpeak];
    } else if (_visible) [self startRaiseToSpeak];
    _input.actionTitle = _joinPending ? NSLocalizedString(@"chat.join", nil) : nil;
    [self.view setNeedsLayout];
}

/* a chat opened from a link carries a channel whose flags do not say whether the account is in, so the button used to flash with the first guess and go;
   getParticipant of this account is the answer, asked once per screen */
- (void)checkMembership {
    if (_membershipAsked || _pinnedList) return;
    _membershipAsked = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadMembershipOfDialog:_dialog completion:^(BOOL member, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: membership of channel %lld was not read: %@", chat->_dialog.peerId, errorName);
            chat->_membershipAsked = NO;
            return;
        }
        [chat applyMembership:member];
    }];
}

/* the wallpaper settings changed: this chat wears its own wallpaper, or the one of every chat, or the background the server gave it, whichever stands now */
- (void)wallpaperDidChange {
    if (!self.isViewLoaded) return;
    NoshiApplyChatWallpaperForChat(_wallpaper, NoshiThemeIsDark(), _dialog.peerKind, _dialog.peerId);
    [_channelWallpaperSignature release];
    _channelWallpaperSignature = nil;
    if (NoshiWallpaperChatHasOwn(_dialog.peerKind, _dialog.peerId)) return;
    [self applyKeptChannelWallpaper];
    if (_channelFull) [self applyChannelWallpaper:_channelFull.wallpaper];
}

/* the background kept from the last visit is painted before the full channel answers, so a chat that has one does not open in the default and change under the eyes */
- (void)applyKeptChannelWallpaper {
    if (!self.isViewLoaded || _channelWallpaperSignature || NoshiWallpaperChatHasOwn(_dialog.peerKind, _dialog.peerId)) return;
    /* the screen, as the wallpaper of every chat uses it: the view bounds are not known yet when the kept one is read, and a size taken from them after layout never
       matched the one asked at the next open, so the kept background was thrown away and the chat stayed plain until the network answered */
    CGSize size = [UIScreen mainScreen].bounds.size;
    NSString *signature = nil;
    UIImage *kept = NoshiCachedChatWallpaper(_dialog.peerKind, _dialog.peerId, size, nil, &signature);
    if (!kept) return;
    _wallpaper.image = kept;
    _channelWallpaperSignature = [signature copy];
}

/* the background the admins gave the channel replaces the one of the app in this chat; a picture waits for its file and then takes the place. what is made is kept, and
   a paper that is the one already shown is left alone */
- (void)applyChannelWallpaper:(noshi_chat_wallpaper)paper {
    /* the wallpaper the person picked for this chat stands over the one the server gave it */
    if (!self.isViewLoaded || NoshiWallpaperChatHasOwn(_dialog.peerKind, _dialog.peerId)) return;
    if (!paper.present) {
        /* the admins took the background away: the kept one goes, and the default comes back */
        NoshiDropChatWallpaper(_dialog.peerKind, _dialog.peerId);
        if (_channelWallpaperSignature) {
            [_channelWallpaperSignature release];
            _channelWallpaperSignature = nil;
            NoshiApplyChatWallpaperForChat(_wallpaper, NoshiThemeIsDark(), _dialog.peerKind, _dialog.peerId);
        }
        return;
    }
    /* the screen, as the wallpaper of every chat uses it: the view bounds are not known yet when the kept one is read, and a size taken from them after layout never
       matched the one asked at the next open, so the kept background was thrown away and the chat stayed plain until the network answered */
    CGSize size = [UIScreen mainScreen].bounds.size;
    BOOL picture = paper.has_file && !paper.pattern;
    NoshiRemoteFile *file = picture ? [NoshiRemoteFile fileForMedia:&paper.file] : nil;
    NSString *signature = NoshiChatWallpaperSignature(&paper, file.key);
    if ([signature isEqualToString:_channelWallpaperSignature]) return;
    int32_t peerKind = _dialog.peerKind;
    long long peerId = _dialog.peerId;
    UIImage *kept = NoshiCachedChatWallpaper(peerKind, peerId, size, signature, NULL);
    if (kept) {
        _wallpaper.image = kept;
        [_channelWallpaperSignature release];
        _channelWallpaperSignature = [signature copy];
        return;
    }
    if (picture) {
        NoshiWeakReference *weak = _weak;
        [_media loadImageForFile:file maxSide:MAX(size.width, size.height) * [UIScreen mainScreen].scale completion:^(UIImage *image) {
            NoshiChatController *chat = weak.target;
            if (!chat || !image) return;
            UIImage *made = NoshiChannelWallpaperImage(&paper, image, size);
            if (!made) return;
            chat->_wallpaper.image = made;
            [chat->_channelWallpaperSignature release];
            chat->_channelWallpaperSignature = [signature copy];
            NoshiStoreChatWallpaper(peerKind, peerId, size, signature, made);
        }];
        return;
    }
    UIImage *made = NoshiChannelWallpaperImage(&paper, nil, size);
    if (!made) return;
    _wallpaper.image = made;
    [_channelWallpaperSignature release];
    _channelWallpaperSignature = [signature copy];
    NoshiStoreChatWallpaper(peerKind, peerId, size, signature, made);
}

- (void)loadChannelFull {
    [self applyKeptChannelWallpaper];
    if (_dialog.topicId > 0 && !_pinnedList) {
        /* the comments of a post are a thread of the discussion group, and the post is what the bar shows there; a topic of a forum shows its pins. the dialog of a
           topic is built with its forum flag cleared, so the discussion flag, which only the comments carry, tells the two apart */
        if (_dialog.discussion) [self loadCommentsPost];
        else [self loadTopicPinned];
    }
    NoshiWeakReference *weak = _weak;
    [_session loadFullChannelOfDialog:_dialog completion:^(NoshiFullChannel *channel, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!channel) {
            NSLog(@"noshigram: channel %lld did not load in full: %@", chat->_dialog.peerId, errorName);
            chat->_channelFullFailed = YES;
            return;
        }
        chat->_channelFullFailed = NO;
        [chat->_channelFull release];
        chat->_channelFull = [channel retain];
        [chat applyChannelWallpaper:channel.wallpaper];
        /* a channel or group the account is not in shows the way in where the field would be */
        /* the flag is only trusted on a full object; a min one says nothing, and the server is asked once */
        if (channel.membershipKnown) [chat applyMembership:!channel.dialog.left];
        else [chat checkMembership];
        [chat refreshStatusLine];
        /* the full channel is the authority on posting rights, whatever the chat list's entry said */
        if (chat->_dialog.kind == NOSHI_DIALOG_CHANNEL) {
            BOOL canPost = channel.dialog.canPost;
            chat->_input.writable = canPost;
            if (!canPost) chat->_input.readOnlyNote = NSLocalizedString(@"chat.readonly", nil);
            [chat.view setNeedsLayout];
        }
        [chat applySendBanOfDialog:channel.dialog];
        [chat applyClosedTopic];
        [chat loadSendAsOptions];
        if (chat->_dialog.topicId > 0) return;
        if (channel.pinnedMessage > 0 && !chat->_pinnedList) {
            [chat loadPinned:channel.pinnedMessage];
            [chat countPinned];
        } else if (!channel.pinnedMessage && chat->_pinnedId && !chat->_pinnedList) {
            /* nothing is pinned any more: the bar goes */
            chat->_pinnedId = 0;
            chat->_pinnedCount = 0;
            chat->_pinnedListButton.hidden = YES;
            [chat setPinnedBarHidden:YES];
        }
    }];
}

/* a group the admins closed to messages, for everyone or for this account, says so where the field would be (the join button of a group not joined yet takes that place first); a ban that ran out is not one, and one that is a year
   away or more reads as for good, as in the official clients */
- (void)applySendBanOfDialog:(NoshiDialog *)dialog {
    if (dialog.kind != NOSHI_DIALOG_GROUP || dialog.sendBan == NOSHI_SEND_OPEN || _pinnedList) return;
    NSString *note = nil;
    if (dialog.sendBan == NOSHI_SEND_BAN_GROUP) {
        note = NSLocalizedString(@"chat.send.banned.group", nil);
    } else {
        NSTimeInterval until = dialog.sendBanUntil, now = [[NSDate date] timeIntervalSince1970];
        if (until != 0 && until <= now) return;
        if (until == 0 || until - now > 366 * 24 * 3600) {
            note = NSLocalizedString(@"chat.send.banned.forever", nil);
        } else {
            NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
            formatter.dateStyle = NSDateFormatterMediumStyle;
            formatter.timeStyle = NSDateFormatterShortStyle;
            note = [NSString stringWithFormat:NSLocalizedString(@"chat.send.banned.until", nil), [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:until]]];
        }
    }
    _input.writable = NO;
    _input.readOnlyNote = note;
    [self.view setNeedsLayout];
}

/* a topic the admins closed takes no messages from anyone but them, so it says so where the field would be, as the official clients do; an admin is known only once the
   full channel is, and gets the field back then */
- (void)applyClosedTopic {
    if (!_dialog.topicClosed || _dialog.topicId <= 0 || _dialog.discussion || _pinnedList) return;
    NSString *note = NSLocalizedString(@"chat.topic.closed", nil);
    if (_channelFull.isAdmin) {
        if ([_input.readOnlyNote isEqualToString:note]) { _input.writable = YES; _input.readOnlyNote = nil; [self.view setNeedsLayout]; }
        return;
    }
    if (!_input.writable) return;
    _input.writable = NO;
    _input.readOnlyNote = note;
    [self.view setNeedsLayout];
}

/* the post the comments belong to heads them: the bar names it, so a long thread need not be scrolled back to its start to read it, and a tap goes to it */
- (void)loadCommentsPost {
    NoshiWeakReference *weak = _weak;
    _pinnedTitle.text = NSLocalizedString(@"chat.comments.post", nil);
    [_session loadMessage:_dialog.topicId ofChannelDialog:_dialog completion:^(NoshiMessage *message, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!message) {
            NSLog(@"noshigram: the post of the comments %d did not load: %@", (int)chat->_dialog.topicId, errorName);
            return;
        }
        [chat->_commentsPost release];
        chat->_commentsPost = [message retain];
        [chat showPinnedMessage:message];
        /* the bar names the channel the post came from; "Post" stays when the origin is not known yet */
        NSString *origin = NoshiForwardName(message, chat->_people);
        if (origin.length) chat->_pinnedTitle.text = origin;
    }];
}

/* the pins of what has no full channel to name them: the open topic of a forum (the full channel names a pin of the whole group, not of the topic), a private chat and a basic group.
   The list of pins is asked for, and the newest stands in the bar */
- (void)loadTopicPinned {
    NSUInteger generation = ++_topicPinnedGeneration;
    NoshiWeakReference *weak = _weak;
    [_session loadPinnedMessagesOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        NoshiChatController *chat = weak.target;
        if (!chat || generation != chat->_topicPinnedGeneration) return;
        if (!messages) {
            NSLog(@"noshigram: pinned messages of topic %d did not load: %@", (int)chat->_dialog.topicId, errorName);
            return;
        }
        chat->_pinnedCount = (NSInteger)messages.count;
        chat->_pinnedListButton.hidden = messages.count < 2;
        NSArray *newestFirst = [messages sortedArrayUsingComparator:^NSComparisonResult(NoshiMessage *a, NoshiMessage *b) {
            return a.messageId < b.messageId ? NSOrderedDescending : (a.messageId > b.messageId ? NSOrderedAscending : NSOrderedSame);
        }];
        [chat->_pinnedAll release];
        chat->_pinnedAll = [newestFirst retain];
        [chat updatePinnedMarker];
        if (messages.count) {
            [chat showPinnedMessage:[newestFirst objectAtIndex:0]];
            [chat refreshPinnedForVisible];
        } else {
            chat->_pinnedId = 0;
            ++chat->_pinnedThumbToken;
            chat->_pinnedThumb.image = nil;
            chat->_pinnedThumb.hidden = YES;
            [chat setPinnedBarHidden:YES];
        }
    }];
}

/* the bars over the list and the strip over the field come and go by growing and shrinking, and the list moves with them; a change of the layout that waited for the next pass made
   the whole chat jump by the height of a bar */
- (void)relayoutAnimatedThen:(void (^)(void))completion {
    if (!self.isViewLoaded || !self.view.window || NoshiReduceMotionEnabled()) {
        [self layoutChat];
        if (completion) completion();
        return;
    }
    void (^done)(void) = [completion copy];
    [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self layoutChat]; } completion:^(BOOL finished) {
        (void)finished;
        if (done) done();
    }];
    [done release];
}

- (void)setPinnedBarHidden:(BOOL)hidden {
    if (hidden) {
        if (_pinnedBar.hidden || _pinnedBarCollapsing) return;
        _pinnedBarCollapsing = YES;
        [self relayoutAnimatedThen:^{
            if (!_pinnedBarCollapsing) return;
            _pinnedBarCollapsing = NO;
            _pinnedBar.hidden = YES;
        }];
        return;
    }
    _pinnedBarCollapsing = NO;
    if (!_pinnedBar.hidden) return;
    _pinnedBar.hidden = NO;
    [self relayoutAnimatedThen:nil];
}

- (void)showPinnedMessage:(NoshiMessage *)message {
    NSString *line = message.text.length ? message.text : NoshiPreviewWord(message.media.kind);
    if (!message.text.length && message.media.kind == NOSHI_PREVIEW_FILE && message.media.name.length) line = message.media.name;
    NSRange newline = [line rangeOfString:@"\n"];
    if (newline.location != NSNotFound) line = [line substringToIndex:newline.location];
    _pinnedId = message.messageId;
    _pinnedText.text = line;
    /* the bar shows the first line, so the custom emoji of that line come with it as their own pictures and not as the plain emoji they stand for */
    NSMutableArray *lineEntities = nil;
    if (message.text.length && [line isEqualToString:[message.text substringToIndex:MIN(line.length, message.text.length)]]) {
        for (NoshiTextEntity *entity in message.entities) {
            if (entity.style != NoshiTextStyleCustomEmoji || NSMaxRange(entity.range) > line.length) continue;
            if (!lineEntities) lineEntities = [NSMutableArray array];
            [lineEntities addObject:entity];
        }
    }
    _pinnedText.entities = lineEntities;
    /* a pinned message that arrives after the history has loaded would otherwise show the plain emoji for good */
    if (lineEntities.count) [self loadCustomEmoji];
    [self updatePinnedMarker];
    [self showPinnedThumbOf:message];
    [self setPinnedBarHidden:line.length == 0];
    [self.view setNeedsLayout];
}

/* the line shows which pin the bar holds among all of them, oldest first, and the title carries the same number once there are several; the post of a thread keeps its own title */
- (void)updatePinnedMarker {
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _pinnedAll.count; i++) {
        if (((NoshiMessage *)[_pinnedAll objectAtIndex:i]).messageId == _pinnedId) { index = i; break; }
    }
    NSInteger total = _pinnedAll.count;
    if (index == NSNotFound || total < 2 || _commentsPost) {
        [_pinnedLine setPosition:0 total:1];
        if (!_commentsPost) _pinnedTitle.text = NSLocalizedString(@"chat.pinned", nil);
        return;
    }
    NSInteger fromOldest = total - 1 - (NSInteger)index;
    [_pinnedLine setPosition:fromOldest total:total];
    _pinnedTitle.text = [NSString stringWithFormat:@"%@ #%ld", NSLocalizedString(@"chat.pinned", nil), (long)(fromOldest + 1)];
}

/* the pinned message is fetched by id, and its first words or the word for its media stand in the bar */
- (void)loadPinned:(int32_t)messageId {
    NoshiWeakReference *weak = _weak;
    [_session loadMessage:messageId ofChannelDialog:_dialog completion:^(NoshiMessage *message, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!message) {
            NSLog(@"noshigram: the pinned message %d of channel %lld did not load: %@", (int)messageId, chat->_dialog.peerId, errorName);
            return;
        }
        [chat showPinnedMessage:message];
    }];
}

/* how many messages the chat has pinned decides whether the bar offers the list of them */
- (void)countPinned {
    NoshiWeakReference *weak = _weak;
    [_session loadPinnedMessagesOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!messages) {
            NSLog(@"noshigram: the pinned messages of chat %lld were not counted: %@", chat->_dialog.peerId, errorName);
            return;
        }
        chat->_pinnedCount = (NSInteger)messages.count;
        chat->_pinnedListButton.hidden = messages.count < 2;
        NSArray *sorted = [messages sortedArrayUsingComparator:^NSComparisonResult(NoshiMessage *a, NoshiMessage *b) {
            return a.messageId < b.messageId ? NSOrderedDescending : (a.messageId > b.messageId ? NSOrderedAscending : NSOrderedSame);
        }];
        [chat->_pinnedAll release];
        chat->_pinnedAll = [sorted retain];
        [chat updatePinnedMarker];
        [chat refreshPinnedForVisible];
        [chat.view setNeedsLayout];
    }];
}

/* with several pins the bar names the one that belongs to what is on screen: the newest pin that is not newer than the top message shown, and once the person has gone up past the oldest
   pin that pin; a chat with one pin keeps showing it */
- (void)refreshPinnedForVisible {
    if (_pinnedAll.count < 2 || _pinnedList || !_items.count) return;
    NSArray *rows = [_table indexPathsForVisibleRows];
    if (!rows.count) return;
    int32_t top = 0;
    for (NSIndexPath *path in rows) {
        if ((NSUInteger)path.row >= _items.count) continue;
        int32_t identifier = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message.messageId;
        if (identifier > 0 && (!top || identifier < top)) top = identifier;
    }
    if (!top) return;
    NoshiMessage *chosen = [_pinnedAll lastObject];
    for (NoshiMessage *pin in _pinnedAll) {
        if (pin.messageId <= top) { chosen = pin; break; }
    }
    if (chosen.messageId != _pinnedId) [self showPinnedMessage:chosen];
}

/* the small square of a pinned photo or video: the photo itself, or the preview of the video, a gif or a sticker */
- (void)showPinnedThumbOf:(NoshiMessage *)message {
    ++_pinnedThumbToken;
    NSUInteger token = _pinnedThumbToken;
    NoshiMedia *media = message.media;
    NoshiRemoteFile *file = media.kind == NOSHI_PREVIEW_PHOTO ? media.file : ((media.kind == NOSHI_PREVIEW_VIDEO || media.kind == NOSHI_PREVIEW_GIF || media.kind == NOSHI_PREVIEW_STICKER || media.kind == NOSHI_PREVIEW_VIDEO_MESSAGE) ? media.previewFile : nil);
    /* a round video keeps its shape in the bar */
    _pinnedThumb.layer.cornerRadius = media.kind == NOSHI_PREVIEW_VIDEO_MESSAGE ? 17 : 6;
    _pinnedThumb.image = nil;
    _pinnedThumb.hidden = file == nil;
    if (!file) return;
    CGFloat pixels = 34 * NoshiScreenScale();
    NoshiWeakReference *weak = _weak;
    [_media loadImageForFile:file maxSide:pixels completion:^(UIImage *image) {
        NoshiChatController *chat = weak.target;
        if (!chat || token != chat->_pinnedThumbToken) return;
        chat->_pinnedThumb.image = image;
        chat->_pinnedThumb.hidden = image == nil;
        [chat.view setNeedsLayout];
    }];
}

- (void)pinnedTapped {
    [self jumpToMessageId:_pinnedId];
}

/* a message that is in the list is scrolled to; one that is older asks for pages of older history until it comes or the pages run out */
- (void)stopJump {
    [_jumpLink invalidate];
    [_jumpLink release];
    _jumpLink = nil;
}

/* where the list has to stand for a row to be in the middle of the screen; a message taller than the screen shows its beginning */
- (CGFloat)aimOffsetForRowRect:(CGRect)rect {
    UIEdgeInsets inset = _table.contentInset;
    CGFloat visible = MAX(1, _table.bounds.size.height - inset.top - inset.bottom);
    CGFloat low = -inset.top;
    CGFloat high = MAX(low, _table.contentSize.height - _table.bounds.size.height + inset.bottom);
    CGFloat aim = rect.size.height >= visible * 0.9 ? rect.origin.y - inset.top - 8 : CGRectGetMidY(rect) - visible / 2 - inset.top;
    return MIN(high, MAX(low, aim));
}

/* the row of a message that was asked for comes to the middle of the screen in a fraction of a second and is lit for a moment. A message far off is first jumped to the
   edge of a screen's distance from it, so the part that is seen is always a short, quick move, and the rows are made as it goes since the offset is set each frame */
- (void)scrollQuicklyToRow:(NSUInteger)row {
    int32_t messageId = ((NoshiChatItem *)[_items objectAtIndex:row]).message.messageId;
    [self stopJump];
    [_table layoutIfNeeded];
    UIEdgeInsets inset = _table.contentInset;
    CGRect rect = [_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    CGFloat visible = MAX(1, _table.bounds.size.height - inset.top - inset.bottom);
    CGFloat low = -inset.top;
    CGFloat high = MAX(low, _table.contentSize.height - _table.bounds.size.height + inset.bottom);
    CGFloat aim = [self aimOffsetForRowRect:rect];
    CGFloat from = _table.contentOffset.y;
    if (_restoringScroll) {
        _restoringScroll = NO;
        /* the kept message is the newest one that was on screen, so it goes back to the bottom edge of the list, where it was; a message taller than the screen shows its beginning */
        CGFloat bottom = rect.size.height >= visible ? rect.origin.y - inset.top - 8 : CGRectGetMaxY(rect) - _table.bounds.size.height + inset.bottom;
        [_table setContentOffset:CGPointMake(0, MIN(high, MAX(low, bottom))) animated:NO];
        return;
    }
    if (NoshiReduceMotionEnabled() || fabs(aim - from) < 1) {
        [_table setContentOffset:CGPointMake(0, aim) animated:NO];
        [self flashRowOfMessage:messageId];
        return;
    }
    CGFloat reach = visible * 1.2f;
    if (fabs(aim - from) > reach) {
        from = MIN(high, MAX(low, aim + (aim > from ? -reach : reach)));
        [_table setContentOffset:CGPointMake(0, from) animated:NO];
        [_table layoutIfNeeded];
    }
    _jumpFrom = from;
    _jumpTo = aim;
    _jumpMessageId = messageId;
    _jumpBegan = 0;
    _jumpLength = 0.2 + 0.14 * MIN(1.0, fabs(aim - from) / reach);
    NoshiReactionPollTarget *target = [[[NoshiReactionPollTarget alloc] initWithReference:_weak] autorelease];
    _jumpLink = [[CADisplayLink displayLinkWithTarget:target selector:@selector(jump:)] retain];
    [_jumpLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)advanceJump:(CADisplayLink *)link {
    /* a finger on the list takes it over */
    if (_table.tracking || _table.dragging) {
        [self stopJump];
        return;
    }
    if (!_jumpBegan) _jumpBegan = link.timestamp;
    /* the row is looked for again at every frame: rows put above it (a page of older messages), a message that came in or a row that changed its height move the row while the list is
       on its way, and the offset worked out when the jump began then led to a place that is not the message */
    for (NSUInteger row = 0; row < _items.count; ++row) {
        if (((NoshiChatItem *)[_items objectAtIndex:row]).message.messageId != _jumpMessageId) continue;
        _jumpTo = [self aimOffsetForRowRect:[_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]]];
        break;
    }
    double t = MIN(1.0, (link.timestamp - _jumpBegan) / _jumpLength);
    double eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
    [_table setContentOffset:CGPointMake(0, (CGFloat)(_jumpFrom + (_jumpTo - _jumpFrom) * eased)) animated:NO];
    if (t < 1.0) return;
    int32_t messageId = _jumpMessageId;
    [self stopJump];
    [self flashRowOfMessage:messageId];
    [self markReadIfNeeded];
    [self loadOlderIfNeeded];
}

- (void)flashRowOfMessage:(int32_t)messageId {
    [_table layoutIfNeeded];
    for (NoshiMessageCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiMessageCell class]] && cell.item.message.messageId == messageId) {
            [cell flashHighlight];
            return;
        }
    }
}

- (int32_t)newestLoadedId {
    int32_t newest = 0;
    for (NSNumber *key in [_server allKeys]) newest = MAX(newest, [key intValue]);
    return newest;
}

- (int32_t)oldestLoadedId {
    int32_t oldest = 0;
    for (NSNumber *key in [_server allKeys]) if ([key intValue] > 0 && (!oldest || [key intValue] < oldest)) oldest = [key intValue];
    return oldest;
}

- (void)scrollToTargetOrLoadMore {
    if (_scrollTarget <= 0) return;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        if (((NoshiChatItem *)[_items objectAtIndex:i]).message.messageId != _scrollTarget) continue;
        _scrollTarget = 0;
        [self stopFollowingBottom];
        _stickToBottom = NO;
        [self scrollQuicklyToRow:i];
        return;
    }
    if (_loadingWindow) return;
    /* the message is held but its row is not built yet, which the rebuild that is waiting does */
    if ([_server objectForKey:[NSNumber numberWithInt:_scrollTarget]]) return;
    /* a message outside what is loaded is opened as the official clients do: the stretch of history around it is fetched and shown, instead of paging through
       everything between it and the newest message, which never got to an old message of a busy group */
    /* older than the oldest message held counts as outside whether or not the page that was last loaded said where the history begins: paging back through a long history for a message
       from years ago stopped after a dozen pages short of it */
    int32_t oldestHeld = [self oldestLoadedId];
    BOOL outside = (_historyOldestId && _scrollTarget < _historyOldestId) || (oldestHeld && _scrollTarget < oldestHeld) || (_window && _scrollTarget > [self newestLoadedId]);
    if (outside && !_pinnedList && !_loadingOlder) {
        [self openWindowAround:_scrollTarget];
        return;
    }
    if (_canLoadMore && !_loadingOlder && _scrollPages++ < PINNED_SEARCH_PAGES) [self loadOlder];
    else if (!_loadingOlder) { _scrollTarget = 0; _restoringScroll = NO; }
}

- (void)openWindowAround:(int32_t)target {
    _loadingWindow = YES;
    NSUInteger token = ++_windowToken;
    NoshiWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog offsetId:target + 1 addOffset:-(HISTORY_PAGE / 2) limit:HISTORY_PAGE pageCompletion:^(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || token != chat->_windowToken) return;
        chat->_loadingWindow = NO;
        BOOL found = NO;
        for (NoshiMessage *message in messages) if (message.messageId == target) found = YES;
        if (!found && messages && chat->_dialog.discussion && chat->_commentsPost.messageId == target && target == chat->_dialog.topicId) {
            messages = [messages arrayByAddingObject:chat->_commentsPost];
            if (!page.oldest_id || target < page.oldest_id) page.oldest_id = target;
            found = YES;
        }
        if (!found) {
            NSLog(@"noshigram: the history around message %d of chat %lld did not hold it: %@", (int)target, chat->_dialog.peerId, errorName);
            chat->_scrollTarget = 0;
            /* a position kept from the last visit may point at a message that is gone since, and that opens the chat at its end without a word */
            if (!chat->_restoringScroll) NoshiShowNotice(nil, NSLocalizedString(@"chat.reply.unavailable", nil));
            chat->_restoringScroll = NO;
            return;
        }
        [chat enterWindowWithMessages:messages people:people page:page];
        [chat scrollToTargetOrLoadMore];
    }];
}

/* the stretch replaces what the list held; older pages and newer pages are fetched from its two ends as the person scrolls */
- (void)enterWindowWithMessages:(NSArray *)messages people:(NSDictionary *)people page:(noshi_history_page)page {
    [self stopFollowingBottom];
    [_server removeAllObjects];
    _historyOldestId = page.oldest_id;
    _window = YES;
    _canLoadNewer = YES;
    _loadingNewer = NO;
    _loadingOlder = NO;
    _olderDeferred = NO;
    _stickToBottom = NO;
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:messages];
    _canLoadMore = _historyOldestId > 1;
    _rebuildNow = YES;
    [self rebuildItems];
    _rebuildNow = NO;
    [_table setContentOffset:CGPointMake(0, -_table.contentInset.top) animated:NO];
    [self showToEnd:YES];
}

- (void)loadNewerIfNeeded:(CGFloat)distance {
    if (_opening || !_window || !_canLoadNewer || _loadingNewer || _loadingWindow || distance > _table.bounds.size.height * 1.5f) return;
    int32_t newest = [self newestLoadedId];
    if (newest <= 0) return;
    _loadingNewer = YES;
    NSUInteger token = _windowToken;
    NoshiWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog offsetId:newest addOffset:-(HISTORY_PAGE - 1) limit:HISTORY_PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || token != chat->_windowToken) return;
        chat->_loadingNewer = NO;
        if (!messages) {
            /* the list stays as it is and the next scroll to its end asks again */
            NSLog(@"noshigram: newer messages of chat %lld not loaded: %@", chat->_dialog.peerId, errorName);
            return;
        }
        NSUInteger fresh = 0;
        for (NoshiMessage *message in messages) if (message.messageId > newest) ++fresh;
        [chat->_people addEntriesFromDictionary:people];
        [chat mergeMessages:messages];
        /* a page that came back short ends at the newest message of the chat: the list is the chat again, and the live updates of the store join it */
        if (fresh + 2 < HISTORY_PAGE) {
            chat->_window = NO;
            chat->_canLoadNewer = NO;
        }
        [chat rebuildItems];
        if (!chat->_window) [chat markReadIfNeeded];
    }];
}

/* back from the window to the end of the chat: what was loaded goes, and the newest page is fetched as when the chat opened */
- (void)leaveWindow {
    if (!_window && !_loadingWindow) return;
    ++_windowToken;
    _window = NO;
    _loadingWindow = NO;
    _loadingNewer = NO;
    _loadingOlder = NO;
    _olderDeferred = NO;
    _canLoadNewer = NO;
    _scrollTarget = 0;
    [_server removeAllObjects];
    _historyOldestId = 0;
    _canLoadMore = NO;
    _loadedFirst = NO;
    _stickToBottom = YES;
    [self loadNewest];
}

#pragma mark voice chat

/* the voice chat of a group or channel is asked for each time the chat comes up, and the bar shows only one this app can join */
- (void)refreshVoiceChat {
    if (_pinnedList || _dialog.saved || (_dialog.peerKind != 2 && _dialog.peerKind != 3) || _joinPending) return;
    NSUInteger token = ++_voiceToken;
    NoshiWeakReference *weak = _weak;
    [_session.groupCalls loadVoiceChatOfDialog:_dialog completion:^(NoshiVoiceChat *chat, NSString *errorName) {
        NoshiChatController *controller = weak.target;
        if (!controller || token != controller->_voiceToken) return;
        if (!chat && errorName && ![errorName isEqualToString:@"NOCALL"]) NSLog(@"noshigram: the voice chat of the chat was not read: %@", errorName);
        [controller->_voiceChat release];
        controller->_voiceChat = [chat retain];
        /* a call nobody is in stays on the full chat after the people left, and the official clients hide the bar for it */
        BOOL show = chat != nil && chat.joinable && chat.participantsCount > 0;
        if (show) controller->_voiceInfo.text = [NSString stringWithFormat:NSLocalizedString(@"group.members", nil), chat.participantsCount];
        if (controller->_voiceBar.hidden == show) {
            controller->_voiceBar.hidden = !show;
            controller->_voiceBar.clipsToBounds = YES;
            [controller relayoutAnimatedThen:nil];
        }
    }];
}

- (void)openVoiceChat {
    if (_voiceChat) {
        [_session.groupCalls joinVoiceChatOfDialog:_dialog inviteHash:nil];
        return;
    }
    [self askWithMessage:NSLocalizedString(@"chat.voice.start.confirm", nil) action:NSLocalizedString(@"chat.menu.voicechat.start", nil) tag:NoshiChatAlertStartVoice];
}

#pragma mark menu

typedef enum { NoshiChatMenuSearch, NoshiChatMenuPinned, NoshiChatMenuVoiceChat, NoshiChatMenuDiscussion, NoshiChatMenuNotifications, NoshiChatMenuWallpaper, NoshiChatMenuClear, NoshiChatMenuBookmarks, NoshiChatMenuSavedDialogs, NoshiChatMenuBotSettings, NoshiChatMenuBotHelp, NoshiChatMenuReport, NoshiChatMenuDelete } NoshiChatMenuEntry;
enum { NoshiChatAlertClear = 9101, NoshiChatAlertDelete, NoshiChatAlertDeleteMessage, NoshiChatAlertSearch, NoshiChatAlertDeleteSelected, NoshiChatAlertStartVoice };

/* asks the question first when the person wants it asked (the setting), then runs the block; declined runs when the answer is no */
- (void)askFirst:(NoshiChatFlag)flag message:(NSString *)message action:(NSString *)action then:(void (^)(void))go declined:(void (^)(void))declined {
    if (!NoshiChatFlagGet(flag)) {
        go();
        return;
    }
    void (^yes)(void) = [go copy];
    void (^no)(void) = [declined copy];
    NoshiShowAlert(nil, message, [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), action, nil], 0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1) yes();
        else if (no) no();
        [yes release];
        [no release];
    });
}

- (void)showChatMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *entries = [NSMutableArray array];
    NoshiSymbol symbols[24];
    BOOL channelLike = _dialog.peerKind == 3;
    BOOL bot = _dialog.kind == NOSHI_DIALOG_BOT;
/* the rows are the ones the three dots give, in its order */
#define MENU_ROW(symbol, key, entry) do { symbols[titles.count] = (symbol); [titles addObject:NSLocalizedString((key), nil)]; [entries addObject:[NSNumber numberWithInt:(entry)]]; } while (0)
    MENU_ROW(NoshiSymbolMagnifier, @"chat.menu.search", NoshiChatMenuSearch);
    MENU_ROW(NoshiSymbolPinLine, @"chat.menu.pinned", NoshiChatMenuPinned);
    if ((_dialog.peerKind == 2 || _dialog.peerKind == 3) && !_dialog.saved && !_pinnedList && !_joinPending) {
        MENU_ROW(NoshiSymbolMicrophone, _voiceChat ? @"chat.menu.voicechat.join" : @"chat.menu.voicechat.start", NoshiChatMenuVoiceChat);
    }
    if (_dialog.saved && !_dialog.savedSource) MENU_ROW(NoshiSymbolGroupsMenu, @"chat.menu.saved.dialogs", NoshiChatMenuSavedDialogs);
    /* the linked chat comes from the full channel, so it waits for it instead of showing a row that cannot work yet */
    if (channelLike && _channelFull.linked) {
        if (_channelFull.megagroup) MENU_ROW(NoshiSymbolMegaphone, @"chat.menu.linked.channel", NoshiChatMenuDiscussion);
        else MENU_ROW(NoshiSymbolGroupsMenu, @"chat.menu.linked.group", NoshiChatMenuDiscussion);
    }
    if (!_dialog.saved) MENU_ROW(NoshiSymbolBell, @"notif.chat.header", NoshiChatMenuNotifications);
    MENU_ROW(NoshiSymbolBackground, @"chat.menu.wallpaper", NoshiChatMenuWallpaper);
    if (!channelLike && _server.count) MENU_ROW(NoshiSymbolClearHistory, @"chat.menu.clear", NoshiChatMenuClear);
    /* the saved messages are listed once the person has marked any is shown only then */
    if ([[NoshiBookmarks bookmarksForSession:_session] entries].count) MENU_ROW(NoshiSymbolFave, @"bookmarks.title", NoshiChatMenuBookmarks);
    if (bot) {
        MENU_ROW(NoshiSymbolSettingsOld, @"chat.menu.bot.settings", NoshiChatMenuBotSettings);
        MENU_ROW(NoshiSymbolHelp, @"chat.menu.bot.help", NoshiChatMenuBotHelp);
        if (!_dialog.saved) MENU_ROW(NoshiSymbolReport, @"report.title", NoshiChatMenuReport);
    }
    if (_dialog.kind == NOSHI_DIALOG_USER || bot || (channelLike && !_joinPending)) {
        MENU_ROW(channelLike ? NoshiSymbolLogout : NoshiSymbolTrash,
                 channelLike ? (_dialog.kind == NOSHI_DIALOG_GROUP ? @"channel.menu.leave.group" : @"channel.menu.leave") : @"chat.menu.delete", NoshiChatMenuDelete);
    }
#undef MENU_ROW
    NSString *deleteTitle = [[entries lastObject] intValue] == NoshiChatMenuDelete ? [titles lastObject] : nil;
    NoshiWeakReference *weak = _weak;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        NoshiChatController *chat = weak.target;
        if (!chat || index >= entries.count) return;
        int entry = [[entries objectAtIndex:index] intValue];
        switch (entry) {
        case NoshiChatMenuSearch: [chat askSearchQuery]; break;
        case NoshiChatMenuPinned: [chat openPinnedList]; break;
        case NoshiChatMenuVoiceChat: [chat openVoiceChat]; break;
        case NoshiChatMenuSavedDialogs: [chat openSavedDialogs]; break;
        case NoshiChatMenuDiscussion: [chat openDiscussion]; break;
        case NoshiChatMenuNotifications:
            [chat.navigationController pushViewController:[[[NoshiNotificationsChatController alloc] initWithSession:chat->_session media:chat->_media peerKind:chat->_dialog.peerKind
                                                                                                              peerId:chat->_dialog.peerId peerHash:chat->_dialog.peerHash
                                                                                                             channel:chat->_dialog.kind == NOSHI_DIALOG_CHANNEL
                                                                                                               topic:chat->_dialog.topicId title:chat->_dialog.title] autorelease] animated:YES];
            break;
        case NoshiChatMenuWallpaper: [chat.navigationController pushViewController:[[[NoshiWallpaperController alloc] initWithPeerKind:chat->_dialog.peerKind peerId:chat->_dialog.peerId] autorelease] animated:YES]; break;
        case NoshiChatMenuClear: [chat askWithMessage:NSLocalizedString(@"chat.clear.confirm", nil) action:NSLocalizedString(@"chat.menu.clear", nil) tag:NoshiChatAlertClear]; break;
        case NoshiChatMenuBookmarks:
            [chat.navigationController pushViewController:[[[NoshiBookmarksController alloc] initWithSession:chat->_session avatars:chat->_avatars media:chat->_media
                                                                                                       stickers:chat->_stickers] autorelease] animated:YES];
            break;
        /* a bot answers its own commands, which is all the settings and the help of a bot are */
        case NoshiChatMenuBotSettings: [chat sendText:@"/settings" entities:nil]; break;
        case NoshiChatMenuBotHelp: [chat sendText:@"/help" entities:nil]; break;
        case NoshiChatMenuReport: [NoshiReportFlow startForDialog:chat->_dialog session:chat->_session host:chat done:nil]; break;
        case NoshiChatMenuDelete: {
            NSString *message = chat->_dialog.peerKind == 3 ? [NSString stringWithFormat:NSLocalizedString(@"chats.swipe.leave.confirm", nil), chat->_dialog.title] : NSLocalizedString(@"chat.delete.confirm", nil);
            [chat askWithMessage:message action:deleteTitle tag:NoshiChatAlertDelete];
            break;
        }
        }
    }] autorelease];
    menu.bottomInset = _keyboardOverlap;
    /* deleting the chat or leaving it is the red button of the sheet */
    if (deleteTitle) menu.destructiveIndex = (NSInteger)titles.count - 1;
    CGPoint anchor;
    if (_menuButton) anchor = [_menuButton.superview convertPoint:CGPointMake(CGRectGetMaxX(_menuButton.frame) - 6, CGRectGetMaxY(_menuButton.frame) - 8) toView:self.view];
    else anchor = CGPointMake(self.view.bounds.size.width - 8, 4);
    [menu showInView:self.view anchor:anchor];
}

- (void)joinChannel {
    if (_joining) return;
    _joining = YES;
    NoshiWeakReference *weak = _weak;
    [_session joinChannelOfDialog:_dialog completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_joining = NO;
        if (errorName) {
            NSLog(@"noshigram: joining %lld failed: %@", chat->_dialog.peerId, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
        chat->_joinPending = NO;
        chat->_membershipAsked = NO;
        chat->_input.actionTitle = nil;
        if (chat->_visible) [chat startRaiseToSpeak];
        /* the full channel is the authority on posting rights and on membership, so it decides what the bar shows now */
        [chat loadChannelFull];
    }];
}

/* the chat made again after the palette changed: the colors are read when the screen is built, so the screen that stands on the right of an ipad takes its new colors this way; the
   place in the chat is kept by the leaving of the old screen and found again by the new one, and the words in the field are kept as a draft */
- (UIViewController *)controllerAfterThemeChange {
    /* a list of pins or of found messages opens again from the chat, which is the page under it */
    if (_pinnedList) return nil;
    /* the old screen may be taken away without a word to its leaving, so what that would save is saved now */
    [self saveDraftNow];
    [self keepScrollPosition];
    NoshiChatController *page = [[[NoshiChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    page.closeHandler = _closeHandler;
    page.nextChatProvider = _nextChatProvider;
    page.startParam = _startParam;
    return page;
}

- (BOOL)showsDialog:(NoshiDialog *)dialog {
    return dialog.peerKind == _dialog.peerKind && dialog.peerId == _dialog.peerId && dialog.topicId == _dialog.topicId;
}

/* the alert with a text field starts at ios 5, which is the lowest this app runs on */
enum { NoshiChatAlertStylePlainTextInput = 2 };

- (void)askSearchQuery {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"chat.search.prompt", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil) otherButtonTitles:NSLocalizedString(@"chat.search.go", nil), nil];
    [alert setAlertViewStyle:NoshiChatAlertStylePlainTextInput];
    [alert setTag:NoshiChatAlertSearch];
    [alert show];
    [alert release];
}

#pragma mark search of the chat

/* the bar takes the place of the header and the strip the place of the field, until Cancel; the matches are looked up a moment after the last key, and the
   chat scrolls to the one that is shown */
- (void)beginChatSearch {
    if (_searchBar) {
        [_searchBar.field becomeFirstResponder];
        return;
    }
    NoshiWeakReference *weak = _weak;
    _searchBar = [[NoshiChatSearchBar alloc] init];
    _searchBar.changeHandler = ^(NSString *text) { [(NoshiChatController *)weak.target chatSearchChanged:text]; };
    _searchBar.cancelHandler = ^{ [(NoshiChatController *)weak.target endChatSearch]; };
    [_header addSubview:_searchBar];
    _searchNav = [[NoshiChatSearchNav alloc] init];
    _searchNav.olderHandler = ^{ [(NoshiChatController *)weak.target stepChatSearch:1]; };
    _searchNav.newerHandler = ^{ [(NoshiChatController *)weak.target stepChatSearch:-1]; };
    [self.view addSubview:_searchNav];
    [self layoutChat];
    [_searchBar.field becomeFirstResponder];
}

- (void)endChatSearch {
    if (!_searchBar) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runChatSearch:) object:nil];
    ++_searchToken;
    [_searchBar.field resignFirstResponder];
    _searchBar.changeHandler = nil;
    _searchBar.cancelHandler = nil;
    _searchNav.olderHandler = nil;
    _searchNav.newerHandler = nil;
    [_searchBar removeFromSuperview];
    [_searchNav removeFromSuperview];
    [_searchBar release];
    [_searchNav release];
    _searchBar = nil;
    _searchNav = nil;
    [_searchHits release];
    _searchHits = nil;
    [self layoutChat];
}

- (void)chatSearchChanged:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runChatSearch:) object:nil];
    ++_searchToken;
    [_searchHits release];
    _searchHits = nil;
    if (!query.length) {
        [_searchNav showIdle];
        return;
    }
    [_searchNav showSearching];
    [self performSelector:@selector(runChatSearch:) withObject:query afterDelay:0.4];
}

- (void)runChatSearch:(NSString *)query {
    if (!_searchBar) return;
    /* the request takes 256 bytes, so the text is cut to a length that fits whatever script it is in */
    NSRange cut = [query rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MIN((NSUInteger)60, query.length))];
    NSUInteger token = ++_searchToken;
    NoshiWeakReference *weak = _weak;
    [_session searchMessagesOfDialog:_dialog query:[query substringWithRange:cut] completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        NoshiChatController *chat = weak.target;
        if (!chat || !chat->_searchBar || token != chat->_searchToken) return;
        if (errorName || !messages.count) {
            if (errorName) NSLog(@"noshigram: chat search failed: %@", errorName);
            [chat->_searchNav showNone];
            return;
        }
        [chat->_searchHits release];
        chat->_searchHits = [messages retain];
        chat->_searchPosition = 0;
        [chat showChatSearchHit];
    }];
}

/* direction 1 goes to an older match, which is further along the list, and -1 to a newer one */
- (void)stepChatSearch:(NSInteger)direction {
    NSInteger next = (NSInteger)_searchPosition + direction;
    if (next < 0 || next >= (NSInteger)_searchHits.count) return;
    _searchPosition = (NSUInteger)next;
    [self showChatSearchHit];
}

- (void)showChatSearchHit {
    [_searchNav showPosition:_searchPosition + 1 of:_searchHits.count];
    NoshiMessage *hit = [_searchHits objectAtIndex:_searchPosition];
    if (hit.messageId > 0) [self jumpToMessageId:hit.messageId];
}

/* the matches open as a list of their own, the way the pinned messages do */
- (void)openSearchResultsFor:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) return;
    /* the request takes 256 bytes, so the text is cut to a length that fits whatever script it is in */
    NSRange cut = [query rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MIN((NSUInteger)60, query.length))];
    NoshiChatController *list = [[[NoshiChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    list.pinnedList = YES;
    list.searchQuery = [query substringWithRange:cut];
    [self.navigationController pushViewController:list animated:YES];
}

/* a tap on a message of a list that came from this chat takes the chat to it */
- (void)messageCellDidTapBody:(NoshiMessageCell *)cell {
    if (!_pinnedList || !cell.item.message) return;
    NSArray *stack = self.navigationController.viewControllers;
    NSUInteger at = [stack indexOfObject:self];
    if (at == NSNotFound || at == 0 || ![[stack objectAtIndex:at - 1] isKindOfClass:[NoshiChatController class]]) return;
    NoshiChatController *chat = [stack objectAtIndex:at - 1];
    if (![chat showsDialog:_dialog]) return;
    int32_t messageId = cell.item.message.messageId;
    [self.navigationController popViewControllerAnimated:YES];
    [chat jumpToMessageId:messageId];
}

/* the action the setting gives a double tap on a message of this direction; what the message does not allow (the mask) does nothing */
- (void)messageCellDidDoubleTap:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    if (!message || message.messageId <= 0) return;
    noshi_action_context context = [self actionContextOfMessage:message];
    uint32_t mask = noshi_message_actions_for(&context);
    noshi_message_action action;
    switch (NoshiChatDoubleTap(message.outgoing)) {
    case NoshiDoubleTapReaction: [self sendQuickReactionToMessage:message]; return;
    case NoshiDoubleTapReactionPicker: action = NOSHI_ACTION_REACT; break;
    case NoshiDoubleTapTranslate: action = NOSHI_ACTION_TRANSLATE; break;
    case NoshiDoubleTapReply: action = NOSHI_ACTION_REPLY; break;
    case NoshiDoubleTapForward: action = NOSHI_ACTION_FORWARD; break;
    case NoshiDoubleTapSave: action = NOSHI_ACTION_SAVE; break;
    case NoshiDoubleTapRepeat: action = NOSHI_ACTION_REPEAT; break;
    case NoshiDoubleTapEdit: action = NOSHI_ACTION_EDIT; break;
    case NoshiDoubleTapDelete: action = NOSHI_ACTION_DELETE; break;
    default: return;
    }
    if (mask & action) [self performAction:action onMessage:message];
}

/* a reaction compares by its emoji without the variation selector, since the server writes the heart with it and a keyboard may not */
static NSString *NoshiBareEmoji(NSString *emoji) {
    return [emoji stringByReplacingOccurrencesOfString:@"\uFE0F" withString:@""];
}

/* the emoji the person chose for the double tap, or the first reaction the chat offers when it is not among them; the list is asked for once, so the first double tap waits for it */
- (void)sendQuickReactionToMessage:(NoshiMessage *)message {
    if (!message.reactionsPossible || [self reactionsHidden]) return;
    int32_t messageId = message.messageId;
    NoshiWeakReference *weak = _weak;
    void (^send)(void) = ^{
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        NSString *selected = NoshiChatQuickReaction();
        long long document = noshi_quick_reaction_document(selected.UTF8String);
        /* a chat that lists its reactions answers REACTION_INVALID to a custom emoji that is not among them */
        BOOL permitted = chat->_menuCustomAllowed;
        for (NoshiReaction *choice in chat->_menuReactions) {
            if (choice.row.kind == NOSHI_REACTION_CUSTOM && choice.row.document_id == document) permitted = YES;
        }
        if (document && permitted && chat->_premiumKnown && chat->_premium) {
            noshi_reaction row;
            memset(&row, 0, sizeof(row));
            row.kind = NOSHI_REACTION_CUSTOM;
            row.document_id = document;
            NSString *alt = NoshiChatQuickReactionDisplay();
            [NoshiReaction rememberCustomTexts:[NSDictionary dictionaryWithObject:alt forKey:[NSNumber numberWithLongLong:document]]];
            [chat chooseReaction:[NoshiReaction reactionWithRow:&row] messageId:messageId burst:NOSHI_BURST_NONE];
            return;
        }
        NSString *wanted = NoshiBareEmoji(selected);
        NoshiReaction *first = nil;
        for (NoshiReaction *choice in chat->_menuReactions) {
            if (choice.row.kind != NOSHI_REACTION_EMOJI) continue;
            if ([NoshiBareEmoji(choice.emoji) isEqualToString:wanted]) {
                [chat chooseReaction:choice messageId:messageId burst:NOSHI_BURST_SHORT];
                return;
            }
            if (!first) first = choice;
        }
        if (first) {
            [chat chooseReaction:first messageId:messageId burst:NOSHI_BURST_SHORT];
        }
    };
    if (_menuReactions) send();
    else [self loadMenuReactionsThen:send];
}

- (void)jumpToMessageId:(int32_t)messageId {
    [self stopScrollForJump];
    _restoringScroll = NO;
    _scrollTarget = messageId;
    _scrollPages = 0;
    [self scrollToTargetOrLoadMore];
}

- (void)stopScrollForJump {
    [self stopFollowingBottom];
    _scrollTarget = 0;
    _restoringScroll = NO;
    if (_table.dragging || _table.decelerating || _interacting) {
        [_table setContentOffset:_table.contentOffset animated:NO];
        [self scrollSettled];
    }
}

/* the chat comes back to the place it was left at: the same scroll as a jump, but the row is not lit and the move is not animated, since the person did not ask for that message */
- (void)restoreScrollToMessageId:(int32_t)messageId {
    _restoringScroll = YES;
    _scrollTarget = messageId;
    _scrollPages = 0;
    [self scrollToTargetOrLoadMore];
}

/* what cannot be undone asks first: a sheet in the modern style, the system alert in the classic one */
- (void)askWithMessage:(NSString *)message action:(NSString *)action tag:(NSInteger)tag {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, message, action, ^{ [(NoshiChatController *)weak.target confirmedTag:tag]; });
}

- (void)confirmedTag:(NSInteger)tag {
    if (tag == NoshiChatAlertStartVoice) {
        [_session.groupCalls startVoiceChatInDialog:_dialog title:nil];
        return;
    }
    if (tag == NoshiChatAlertDeleteSelected) {
        [self deleteSelectedNow];
        return;
    }
    if (tag == NoshiChatAlertDeleteMessage) {
        [self deleteMessageNow];
        return;
    }
    BOOL clear = tag == NoshiChatAlertClear;
    NoshiWeakReference *weak = _weak;
    [_session performAction:clear ? NoshiChatCommandClear : NoshiChatCommandDelete onDialog:_dialog completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
        if (clear) [chat didClearHistory];
        else [chat goBack];
    }];
}

/* the text input of the search is the one alert that is left; the questions about deleting are sheets, or alerts the confirm helper owns */
- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    if (index == [alert cancelButtonIndex] || [alert tag] != NoshiChatAlertSearch) return;
    [self openSearchResultsFor:[[alert textFieldAtIndex:0] text]];
}

/* what the screen held is gone with the history on the server, and no older page is left to fetch */
- (void)didClearHistory {
    [_server removeAllObjects];
    [_local removeAllObjects];
    [_replyCache removeAllObjects];
    ++_replyGeneration;
    _loadingReplies = NO;
    _historyOldestId = 0;
    _canLoadMore = NO;
    [self rebuildItems];
    [self showEmptyState];
}

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

- (void)messageCellDidTapShare:(NoshiMessageCell *)cell {
    int32_t messageId = cell.item.message.messageId;
    if (!_channelFull.username.length) {
        NoshiGiftAlert(nil, NSLocalizedString(@"chat.share.nolink", nil));
        return;
    }
    [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://t.me/%@/%d", _channelFull.username, (int)messageId];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

- (void)messageCellDidTapComments:(NoshiMessageCell *)cell {
    if (_dialog.replies) {
        [self openOriginOfRepliesMessage:cell.item.message];
        return;
    }
    if (_openingComments || cell.item.message.messageId <= 0) return;
    _openingComments = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadDiscussionOfPost:cell.item.message.messageId dialog:_dialog completion:^(NoshiDialog *thread, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_openingComments = NO;
        if (!thread) {
            NSLog(@"noshigram: post discussion did not load: %@", errorName);
            /* the server answers a post that was deleted, or whose discussion message was, with an invalid message id */
            BOOL gone = [errorName isEqualToString:@"MSG_ID_INVALID"] || [errorName isEqualToString:@"MESSAGE_ID_INVALID"];
            NoshiGiftAlert(nil, NSLocalizedString(gone ? @"chat.comments.deleted" : @"chat.comments.unavailable", nil));
            return;
        }
        if (!chat->_visible) return;
        NoshiChatController *discussion = [[[NoshiChatController alloc] initWithSession:chat->_session dialog:thread avatars:chat->_avatars media:chat->_media stickers:chat->_stickers] autorelease];
        [chat.navigationController pushViewController:discussion animated:YES];
    }];
}

/* the "open chat" row of a message of the replies: the group the comment was written in, at the comment. A reply comes only from a group, so a channel in the header is a
   supergroup; its access hash is not in the header and comes with the message from the server */
- (void)openOriginOfRepliesMessage:(NoshiMessage *)message {
    long long peerId = message.forwardOriginId;
    int32_t kind = message.forwardOriginKind;
    int32_t target = message.forwardOriginMessage;
    if ((kind != 2 && kind != 3) || peerId <= 0 || target <= 0) {
        [self toast:NSLocalizedString(@"chat.replies.unavailable", nil)];
        return;
    }
    NoshiPerson *known = kind == 3 ? [_people objectForKey:[NSNumber numberWithLongLong:-peerId]] : nil;
    if (kind == 2 || known.accessHash) {
        [self pushOriginChatOfKind:kind peerId:peerId hash:known.accessHash person:known messageId:target];
        return;
    }
    if (_openingComments) return;
    _openingComments = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadChannelSender:peerId ofMessage:message.messageId inDialog:_dialog completion:^(NoshiPerson *group, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_openingComments = NO;
        if (!group) {
            NSLog(@"noshigram: the chat of a reply did not load: %@", errorName);
            [chat toast:NSLocalizedString(@"chat.replies.unavailable", nil)];
            return;
        }
        [chat->_people setObject:group forKey:[NSNumber numberWithLongLong:-peerId]];
        if (chat->_visible) [chat pushOriginChatOfKind:3 peerId:peerId hash:group.accessHash person:group messageId:target];
    }];
}

- (void)pushOriginChatOfKind:(int32_t)kind peerId:(long long)peerId hash:(long long)hash person:(NoshiPerson *)person messageId:(int32_t)messageId {
    noshi_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = kind;
    row.peer_id = peerId;
    row.peer_hash = hash;
    row.kind = NOSHI_DIALOG_GROUP;
    row.verified = person.verified;
    if (person.photo) row.photo = person.photo.ref;
    snprintf(row.title, sizeof(row.title), "%s", person.name.UTF8String ? person.name.UTF8String : "");
    NoshiDialog *dialog = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
    NoshiChatController *origin = [[[NoshiChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    origin.startMessageId = messageId;
    [self.navigationController pushViewController:origin animated:YES];
}

- (void)openDiscussion {
    NoshiDialog *linked = _channelFull.linked;
    if (!linked) return;
    NoshiChatController *discussion = [[[NoshiChatController alloc] initWithSession:_session dialog:linked avatars:_avatars media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:discussion animated:YES];
}

- (void)goBack {
    [_input.textView resignFirstResponder];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark orientation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return NoshiOrientationMask();
}
#pragma clang diagnostic pop

#pragma mark layout

- (CGFloat)panelHeight {
    CGSize windowSize = self.view.window ? self.view.window.bounds.size : [UIScreen mainScreen].bounds.size;
    BOOL landscape = windowSize.width > windowSize.height;
    if (NoshiIsPad()) return landscape ? 352 : 264;
    return landscape ? 162 : 216;
}

- (void)layoutChat {
    if (_layingOutChat) return;
    _layingOutChat = YES;
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    /* the wallpaper and the bar plate run full width; everything that is read or touched stands in one column, clear of the notch in landscape and no wider
       than a message reads on a tablet */
    CGRect column = NoshiContentColumn(size, insets, NOSHI_COLUMN_CHAT);
    CGFloat left = column.origin.x, width = column.size.width, edge = CGRectGetMaxX(column);
    /* a classic chat sits under the system's own bar, which the view already starts below or reports in the top inset */
    CGFloat headerHeight = insets.top;
    CGFloat pinnedHeight = _pinnedBar.hidden || _pinnedBarCollapsing ? 0 : PINNED_HEIGHT;
    /* ios 5 sometimes loses the announcement of the keyboard going down (a panel or a keyboard taken away while another screen was over the chat), and the field then stays
       where the keyboard was, in the middle of the screen over an empty bar. with nothing to type in and no slide running, there is no keyboard to make room for */
    if (_keyboardOverlap > 0 && !_keyboardMoving && !_panelShown && ![_input.textView isFirstResponder]) _keyboardOverlap = 0;
    CGFloat bottomPad = _keyboardOverlap > 0 ? 0 : insets.bottom;
    BOOL hideReadOnly = _dialog.kind == NOSHI_DIALOG_CHANNEL && !_input.writable && !_input.actionTitle.length;
    BOOL searching = _searchBar != nil;
    _input.hidden = _pinnedList || hideReadOnly || _selecting || searching;
    CGFloat inputHeight = _pinnedList ? 0 : (searching ? NOSHI_CHAT_SEARCH_NAV_HEIGHT : (_selecting ? [NoshiSelectionBar height] : (hideReadOnly ? 0 : [_input preferredHeight])));
    CGFloat inputY = size.height - _keyboardOverlap - bottomPad - inputHeight;
    /* the strip that names what the next send answers or changes stands right over the field, and the list ends above it */
    CGFloat contextHeight = _context.hidden || _pinnedList ? 0 : [NoshiComposeContext height];
    _context.frame = CGRectMake(left, inputY - contextHeight, width, contextHeight);
    _reactionPicker.frame = self.view.bounds;
    _wallpaper.frame = self.view.bounds;
    _header.frame = CGRectMake(0, 0, size.width, headerHeight);
    _headerLine.frame = CGRectMake(0, headerHeight - 1.0 / NoshiScreenScale(), size.width, 1.0 / NoshiScreenScale());
    /* the only page of the right pane of a tablet has no left pane to go back to, so the title moves into the room the arrow leaves */
    BOOL alone = NoshiIsDetailRoot(self);
    CGFloat badge = [self backBadgeWidth];
    /* the count stands against the arrow, and the picture and the name move over by what it takes beyond the room the arrow leaves */
    CGFloat shift = alone ? 36 : -MAX(0, badge - 14);
    _back.hidden = alone;
    _back.frame = CGRectMake(left, insets.top, 52, BAR_HEIGHT);
    _backBadge.frame = CGRectMake(left + 30, insets.top + 9, badge, 18);
    _avatar.frame = CGRectMake(left + 48 - shift, insets.top + 5, 34, 34);
    _storyRing.frame = CGRectInset(_avatar.frame, -3, -3);
    /* the classic icon stands in the box of the bar item, and this layout would move it to the place of the header's picture, outside the box where nothing shows it */
    _menuButton.frame = CGRectMake(edge - 48, insets.top, 44, BAR_HEIGHT);
    CGFloat textX = left + (_pinnedList ? 60 : 90) - shift, textWidth = edge - textX - (_pinnedList ? 12 : 56);
    BOOL hasStatus = _subtitle.text.length > 0;
    _title.font = NoshiFontSemibold(17);
    _subtitle.font = NoshiFontRegular(13);
    _title.frame = CGRectMake(textX, insets.top + (hasStatus ? 4 : 11), textWidth, 22);
    _subtitle.frame = CGRectMake(textX, insets.top + 25, textWidth, 16);
    _input.frame = CGRectMake(left, inputY, width, inputHeight + bottomPad);
    _searchBar.frame = CGRectMake(0, 0, size.width, headerHeight - 1.0 / NoshiScreenScale());
    _searchNav.frame = CGRectMake(left, inputY, width, inputHeight + bottomPad);
    _selectionBar.frame = _input.frame;
    BOOL wasBottom = _stickToBottom;
    CGRect previousViewport = _table.frame;
    CGFloat previousOffset = _table.contentOffset.y;
    _pinnedBar.frame = CGRectMake(left, headerHeight, width, pinnedHeight);
    UIView *pinnedFoot = [_pinnedBar viewWithTag:PINNED_FOOT_TAG];
    pinnedFoot.frame = CGRectMake(0, pinnedHeight - 1.0 / NoshiScreenScale(), width, 1.0 / NoshiScreenScale());
    _pinnedTitle.font = NoshiFontSemibold(13);
    _pinnedText.font = NoshiFontRegular(14);
    CGFloat pinnedX = _pinnedThumb.hidden ? 24 : 24 + 34 + 10;
    CGFloat pinnedRight = _pinnedListButton.hidden ? 12 : 52;
    _pinnedLine.frame = CGRectMake(12, 0, 2, PINNED_HEIGHT);
    _pinnedThumb.frame = CGRectMake(24, (PINNED_HEIGHT - 34) / 2, 34, 34);
    _pinnedListButton.frame = CGRectMake(width - 48, 0, 44, PINNED_HEIGHT);
    _pinnedTitle.frame = CGRectMake(pinnedX, 6, width - pinnedX - pinnedRight, 17);
    _pinnedText.frame = CGRectMake(pinnedX, 24, width - pinnedX - pinnedRight, 18);
    _toEnd.frame = CGRectMake(CGRectGetMaxX(column) - 56, inputY - contextHeight - 56, 44, 44);
    [self placeReactionJump];
    headerHeight += pinnedHeight;
    /* the pinned message stands right under the header and the strip is a pill under it, over the voice bar, as in the android client, which also gives the chat list beside it on a tablet a strip of its own */
    CGFloat listTop = headerHeight;
    CGFloat playerHeight = _miniPlayer.showing ? [NoshiMiniPlayer heightForPill:YES] : 0;
    /* a strip that is collapsing stays in the tree until its height reaches zero, which its own animation finishes */
    _miniPlayer.hidden = (!_miniPlayer.showing && _miniPlayer.frame.size.height < 1);
    _miniPlayer.frame = CGRectMake(left, headerHeight, width, playerHeight);
    headerHeight += playerHeight;
    _toast.frame = CGRectMake(CGRectGetMidX(column) - 60, headerHeight + 10, 120, 28);
    CGFloat voiceHeight = _voiceBar.hidden ? 0 : VOICE_HEIGHT;
    _voiceBar.frame = CGRectMake(left, headerHeight, width, voiceHeight);
    _voiceTitle.font = NoshiFontSemibold(14);
    _voiceInfo.font = NoshiFontRegular(12);
    _voiceJoin.font = NoshiFontSemibold(13);
    _voiceJoin.frame = CGRectMake(width - 112, (VOICE_HEIGHT - 28) / 2, 100, 28);
    _voiceTitle.frame = CGRectMake(24, 5, width - 150, 18);
    _voiceInfo.frame = CGRectMake(24, 23, width - 150, 16);
    headerHeight += voiceHeight;
    /* the list starts under the pill and the voice bar and keeps its first message clear of them with an inset, so the messages show through the gaps and the translucent card instead of being cut off at a hard edge */
    CGRect viewport = CGRectMake(left, listTop, width, MAX(0, inputY - contextHeight - listTop));
    if (!CGRectEqualToRect(_table.frame, viewport)) _table.frame = viewport;
    BOOL typingWasShown = _typingShown;
    [self placeTypingBubble];
    if (typingWasShown != _typingShown && wasBottom && !_interacting && !_table.dragging && !_table.decelerating) [self scrollToBottomAnimated:NO];
    UIView *suggestions = _bots.panel;
    if (suggestions) {
        CGFloat room = [_bots panelHeightForWidth:width maxHeight:MAX(0, inputY - headerHeight)];
        suggestions.frame = CGRectMake(left, inputY - room, width, room);
    }
    [_bots layoutCardInRect:CGRectMake(left, headerHeight, width, MAX(0, inputY - headerHeight))];
    UIEdgeInsets contentInset = UIEdgeInsetsMake(6 + headerHeight - listTop, 0, 6, 0);
    if (!UIEdgeInsetsEqualToEdgeInsets(_table.contentInset, contentInset)) {
        /* a list that stands at its first message follows the inset down, one that is read further on stays where it is */
        BOOL atFirst = fabs(_table.contentOffset.y + _table.contentInset.top) < 1;
        _table.contentInset = contentInset;
        _table.scrollIndicatorInsets = UIEdgeInsetsMake(contentInset.top, 0, 0, 0);
        if (atFirst && !_table.dragging && !_table.decelerating) _table.contentOffset = CGPointMake(0, -contentInset.top);
    }
    CGPoint middle = CGPointMake(CGRectGetMidX(column), headerHeight + (inputY - headerHeight) / 2);
    CGSize fit = [_status sizeThatFits:CGSizeMake(MIN(width - 64, 420), 200)];
    _status.font = NoshiFontRegular(16);
    _status.frame = CGRectMake(middle.x - fit.width / 2, middle.y - fit.height / 2 - (_retry.hidden ? 0 : 22), fit.width, fit.height);
    if (_premiumGate) {
        CGSize gate = [_premiumGate cardSizeForWidth:width];
        _premiumGate.frame = CGRectMake(middle.x - gate.width / 2, middle.y - gate.height / 2, gate.width, gate.height);
    }
    if (_greeting) {
        _greeting.hidden = _items.count > 0 || _premiumGate != nil;
        CGSize card = [_greeting cardSizeForWidth:width];
        _greeting.frame = CGRectMake(middle.x - card.width / 2, middle.y - card.height / 2, card.width, card.height);
    }
    _retry.titleLabel.font = NoshiFontSemibold(17);
    _retry.frame = CGRectMake(middle.x - 70, CGRectGetMaxY(_status.frame) + 8, 140, 40);
    if (width != _laidOutWidth) {
        _laidOutWidth = width;
        for (NoshiChatItem *item in _items) [item invalidateLayout];
        [_table reloadData];
    }
    BOOL touching = _interacting || _table.dragging || _table.decelerating;
    if (wasBottom && !touching && !CGRectEqualToRect(previousViewport, _table.frame)) {
        [self scrollToBottomAnimated:NO];
    } else if (!wasBottom && !touching && _items.count && previousViewport.size.width == _table.frame.size.width) {
        CGFloat shrink = previousViewport.size.height - _table.frame.size.height;
        if (shrink != 0) {
            [_table layoutIfNeeded];
            double next = 0;
            /* UIKit may already clamp the offset when the keyboard closes, so adding the height to its new offset moves twice */
            noshi_status status = noshi_scroll_resize(previousOffset, previousViewport.size.height, _table.bounds.size.height,
                                                          [self scrollLimitMin], [self scrollLimitMax], &next);
            if (status == NOSHI_OK) [_table setContentOffset:CGPointMake(0, (CGFloat)next) animated:NO];
            else NSLog(@"noshigram: chat viewport resize failed: %s", noshi_status_name(status));
        }
    }
    if (!CGRectEqualToRect(previousViewport, _table.frame))
        noshi_scroll_begin(&_scroll, _table.contentOffset.y, CFAbsoluteTimeGetCurrent());
    _layingOutChat = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_panel) {
        CGFloat width = _panel.superview ? _panel.superview.bounds.size.width : self.view.window.bounds.size.width;
        if (width <= 0) width = [UIScreen mainScreen].bounds.size.width;
        CGRect frame = _panel.frame;
        frame.size = CGSizeMake(width, [self panelHeight]);
        if (!CGRectEqualToRect(frame, _panel.frame)) _panel.frame = frame;
    }
    [self layoutChat];
}

- (void)inputBarDidChangeHeight:(NoshiInputBar *)bar {
    (void)bar;
    /* a field that grows with the words, so the move is short and starts from where the last one is */
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{ [self layoutChat]; } completion:nil];
}

#pragma mark keyboard

/* the count of the other chats: this one is left out, since it is the one that is read now */
/* the width of the name in the classic bar. the bar centers it, so it can take only what is left beside the wider side: the back arrow with its count on one side, the picture
   and the dots on the other. the 190 points of the default run under the picture on a phone 320 points wide */
- (CGFloat)classicTitleWidth {
    if (NoshiIsPad()) return 420;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    /* a long count (999+) makes the left side wider than the default, and the centered name gives up as much on the right, or it would run under the count */
    CGFloat side = CLASSIC_BAR_SIDE_WIDTH;
    if (_classicCounterWidth > 0) side = MAX(side, CLASSIC_BACK_PLATE + CLASSIC_COUNTER_GAP + _classicCounterWidth + 12);
    return MAX(60, MIN(190, MIN(screen.width, screen.height) - 2 * side));
}

/* the back button is the chevron of ios 7, and the count of the other unread chats stands in a flat capsule of its own right beside it, since a system item cannot hold a badge */
- (void)refreshClassicBackWithCount:(NSInteger)count {
    UIBarButtonItem *item = [[[UIBarButtonItem alloc] initWithImage:NoshiBackChevronImage() style:UIBarButtonItemStylePlain target:self action:@selector(goBack)] autorelease];
    item.accessibilityLabel = NSLocalizedString(@"phone.back", nil);
    CGFloat counterWidth = 0;
    if (count <= 0) {
        self.navigationItem.leftBarButtonItems = [NSArray arrayWithObject:item];
    } else {
        UIView *badge = NoshiClassicCounterBadge(count > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)count]);
        UIBarButtonItem *counter = [[[UIBarButtonItem alloc] initWithCustomView:badge] autorelease];
        /* the two items are placed edge to edge by the bar, so the plate of the arrow and the count ran together; a gap of its own keeps them apart */
        UIBarButtonItem *gap = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:NULL] autorelease];
        gap.width = CLASSIC_COUNTER_GAP;
        counterWidth = badge.frame.size.width;
        self.navigationItem.leftBarButtonItems = [NSArray arrayWithObjects:item, gap, counter, nil];
    }
    if (fabs(counterWidth - _classicCounterWidth) > 0.5) {
        _classicCounterWidth = counterWidth;
        /* the name was made for the old count; while the view is still being made it is made once, after this */
        if ([self isViewLoaded]) [self installClassicTitleView];
    }
}

- (void)refreshBackBadge {
    NSInteger count = NoshiUnreadTotal();
    if (_dialog.unread && !_dialog.muted && !_dialog.folder) count -= _dialog.unreadCount;
    if (_classicBack) {
        [self refreshClassicBackWithCount:MAX(0, count)];
        return;
    }
    if (!_backBadge) return;
    BOOL show = count > 0 && !NoshiIsDetailRoot(self);
    NSString *text = count > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)count];
    if (show) _backBadge.text = text;
    BOOL changed = _backBadge.hidden == show;
    _backBadge.hidden = !show;
    if (changed) [self.view setNeedsLayout];
}

- (void)unreadTotalChanged:(NSNotification *)note {
    (void)note;
    [self refreshBackBadge];
}

- (CGFloat)backBadgeWidth {
    return !_backBadge || _backBadge.hidden ? 0 : MAX(18, ceil([_backBadge.text sizeWithFont:_backBadge.font].width) + 12);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* the full channel carries the background of the group; when its answer or the picture of the background was lost, the next appearance asks again instead of leaving the chat plain */
    if (_dialog.peerKind == 3 && _channelFullFailed) { _channelFullFailed = NO; [self loadChannelFull]; }
    else if (_channelFull && !_channelWallpaperSignature) [self applyChannelWallpaper:_channelFull.wallpaper];
    /* no screen over the whole display is up, so a bar one of them left hidden comes back */
    NoshiStatusBarSettle();
    [self refreshBackBadge];
    _visible = YES;
    [self rebuildItems];
    [self refreshVoiceChat];
    [self loadTopicMessageCount];
    NoshiNotifierSetOpenChat(_dialog.peerKind, _dialog.peerId);
    if (!_reactionTimer) {
        NoshiReactionPollTarget *target = [[[NoshiReactionPollTarget alloc] initWithReference:_weak] autorelease];
        _reactionTimer = [[NSTimer scheduledTimerWithTimeInterval:20 target:target selector:@selector(fire:) userInfo:nil repeats:YES] retain];
    }
    if (!_observing) {
        _observing = YES;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(applicationBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(applicationResignedActive) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(refreshStatusLine) name:NoshiSessionConnectionDidChangeNotification object:_session];
        [center addObserver:self selector:@selector(typingChanged:) name:NoshiTypingDidChangeNotification object:_session.typing];
    }
    [self refreshStatusLine];
    [self startRaiseToSpeak];
    /* a swipe that carried on while another screen covered the list may never report its end */
    if (_interacting && !_table.dragging && !_table.decelerating) [self scrollSettled];
    [self flushLiveMessages];
    [self refreshAnimations];
    [self performSelector:@selector(markReadIfNeeded) withObject:nil afterDelay:0];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* visible rows are unavailable until the table has entered the window */
    [_table layoutIfNeeded];
    [self markReadIfNeeded];
}

static NSString *const NoshiChatScrollKey = @"noshigram.chat.scrollpos";
#define CHAT_SCROLL_KEPT_MAX 200
/* a list this near its end counts as at its end: the finger rule of the flag and the place kept on leaving both go by it */
#define BOTTOM_FOLLOW_DISTANCE 80.0

- (NSString *)scrollKey {
    return [NSString stringWithFormat:@"%d:%lld:%d", (int)_dialog.peerKind, _dialog.peerId, (int)_dialog.topicId];
}

- (int32_t)keptScrollMessageId {
    NSDictionary *entry = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiChatScrollKey] objectForKey:[self scrollKey]];
    return [[entry objectForKey:@"id"] intValue];
}

/* leaving a chat that is not at its end keeps the newest message on screen, and leaving it at the end forgets any place; only the most recent chats are kept */
- (void)keepScrollPosition {
    if (_pinnedList || !_items.count || !_table.window) return;
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiChatScrollKey]];
    NSString *key = [self scrollKey];
    int32_t shown = 0;
    /* the flag follows only a finger, so a list that a layout, a keyboard or a new message left near its end could have it off, and the next opening was thrown back to a message
       a page above the newest; the offset says where the list is */
    BOOL atEnd = !_window && [self scrollLimitMax] - _table.contentOffset.y <= BOTTOM_FOLLOW_DISTANCE;
    if (!_stickToBottom && !atEnd) {
        for (NSIndexPath *path in _table.indexPathsForVisibleRows) {
            if ((NSUInteger)path.row >= _items.count) continue;
            NoshiMessage *message = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
            if (message.messageId > shown) shown = message.messageId;
        }
    }
    if (shown > 0) {
        [all setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:shown], @"id", [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"at", nil] forKey:key];
        while (all.count > CHAT_SCROLL_KEPT_MAX) {
            NSString *oldest = nil;
            double oldestAt = 0;
            for (NSString *candidate in all) {
                double at = [[[all objectForKey:candidate] objectForKey:@"at"] doubleValue];
                if (!oldest || at < oldestAt) { oldest = candidate; oldestAt = at; }
            }
            [all removeObjectForKey:oldest];
        }
    } else {
        [all removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:NoshiChatScrollKey];
}

- (void)viewWillDisappear:(BOOL)animated {
    if (_typingSent) { [_session setTyping:NO inDialog:_dialog]; _typingSent = NO; }
    [self clearTextSelection];
    [super viewWillDisappear:animated];
    ++_codeCopyToken;
    _visible = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sharingExpiryReached) object:nil];
    [self stopFollowingBottom];
    [_liveLink invalidate];
    [_liveLink release];
    _liveLink = nil;
    NoshiNotifierSetOpenChat(0, 0);
    [self stopRaiseToSpeak];
    [self discardRecording];
    [_reactionTimer invalidate];
    [_reactionTimer release];
    _reactionTimer = nil;
    [self closeReactionPicker];
    [self stopAnimations];
    [self saveDraftNow];
    [self keepScrollPosition];
    if ([self isMovingFromParentViewController]) {
        [_session stopWatchingForOwner:self];
        if (_closeHandler) _closeHandler();
    }
}

#pragma mark raise to speak

/* with "raise to speak" the phone held to the ear in a chat records a voice message and lowering it sends it */
- (void)startRaiseToSpeak {
    if (_raiseWatching || _joinPending || !NoshiChatRaiseToSpeak() || !_input.writable) return;
    if (!NoshiProximityStart()) return;
    _raiseWatching = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(raiseChanged) name:NoshiProximityDidChangeNotification object:nil];
}

- (void)stopRaiseToSpeak {
    if (!_raiseWatching) return;
    _raiseWatching = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiProximityDidChangeNotification object:nil];
    if (_raiseRecording) {
        _raiseRecording = NO;
        [_input endRaisedRecordingCancelled:YES];
    }
    NoshiProximityStop();
}

- (void)raiseChanged {
    BOOL near = NoshiProximityNear();
    if (near && !_raiseRecording) {
        if (!NoshiPhoneIsUpright() || [NoshiMusicPlayer sharedPlayer].state == NoshiMusicStatePlaying) return;
        if ([_input beginRaisedRecording]) _raiseRecording = YES;
    } else if (!near && _raiseRecording) {
        _raiseRecording = NO;
        [_input endRaisedRecordingCancelled:NO];
    }
}

- (void)applicationBecameActive {
    if (_visible) [self rebuildItems];
    [self flushLiveMessages];
    [self refreshAnimations];
    if (_visible) {
    }
    [self markReadIfNeeded];
    [self pollReactions];
}

- (void)timesChanged {
    [_itemCache removeAllObjects];
    [self rebuildItems];
}

- (void)applicationResignedActive {
    if (_typingSent) { [_session setTyping:NO inDialog:_dialog]; _typingSent = NO; }
    [self saveDraftNow];
    [self stopAnimations];
    [self stopFollowingBottom];
    [_liveLink invalidate];
    [_liveLink release];
    _liveLink = nil;
}

- (void)keyboardChanged:(NSNotification *)note {
    UIWindow *window = self.view.window;
    if (!window) return;
    NSDictionary *info = note.userInfo;
    CGFloat overlap = 0;
    if ([note.name isEqualToString:UIKeyboardWillChangeFrameNotification]) {
        CGRect end = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGRect inView = [self.view convertRect:[window convertRect:end fromWindow:nil] fromView:window];
        overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - inView.origin.y);
    }
    [self slideKeyboardOverlapTo:overlap duration:[[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]
                           curve:[[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue]];
}

- (void)slideKeyboardOverlapTo:(CGFloat)overlap duration:(NSTimeInterval)duration curve:(NSInteger)curve {
    /* a hide is announced twice (the frame change and the hide), and a second animation over the first one only restarts it */
    if (overlap == _keyboardOverlap) return;
    _keyboardOverlap = overlap;
    /* the offset UIKit clamps while the table is resized, and a page of messages that lands in the middle of the slide, both read as the chat jumping */
    _keyboardMoving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(keyboardSettled) object:nil];
    [self performSelector:@selector(keyboardSettled) withObject:nil afterDelay:duration + 0.05];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{ [self layoutChat]; } completion:nil];
}

- (void)keyboardSettled {
    _keyboardMoving = NO;
    if (_livePending) [self scheduleLiveMessages];
}

- (void)inputBarDidBeginEditing:(NoshiInputBar *)bar {
    (void)bar;
    /* a person reading old messages keeps their place when they tap the field */
    if (_stickToBottom) [self scrollToBottomAnimated:NO];
}

/* the emoji panel is our own input view, and the system does not announce its hide with a frame the field can follow when the field loses focus by any way but
   dismissInput (a screen pushed over the chat, endEditing, a sheet): the field stayed where the panel was. A system keyboard announces itself, and the equal
   overlap check of the slide keeps the second move away */
- (void)inputBarDidEndEditing:(NoshiInputBar *)bar {
    (void)bar;
    if (!_panelShown) return;
    _panelShown = NO;
    _input.panelShown = NO;
    _input.textView.inputView = nil;
    [self slideKeyboardOverlapTo:0 duration:0.25 curve:7];
}

#pragma mark panel

/* a tap on the list while a message is edited with the emoji panel open takes the person back to the keyboard of the edit, where it was left, instead of putting
   the field away and leaving the chat with an edit nobody can see */
- (void)listTapped {
    if (_editingId && _panelShown) {
        [self inputBarDidTapPanelButton:_input];
        return;
    }
    [self dismissInput];
}

- (void)dismissInput {
    BOOL hadPanel = _panelShown;
    if (_panelShown) {
        _panelShown = NO;
        _input.panelShown = NO;
        _input.textView.inputView = nil;
    }
    [_input.textView resignFirstResponder];
    /* the panel is our own input view, and the system does not always announce its hide with a frame the field can follow: the panel went down by itself while the
       field stayed where it was. the field is moved here, at the pace of the system keyboard, and the announcement that may come after finds nothing left to do */
    if (hadPanel) [self slideKeyboardOverlapTo:0 duration:0.25 curve:7];
}

- (NoshiInputPanel *)panel {
    if (!_panel) {
        _panel = [[NoshiInputPanel alloc] initWithMedia:_media library:_stickers];
        _panel.delegate = self;
        CGFloat width = self.view.window ? self.view.window.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
        _panel.frame = CGRectMake(0, 0, width, [self panelHeight]);
        _panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [_panel enableEmojiSearchWithSession:_session];
        [_panel enableGifsWithSession:_session media:_media library:_stickers dialog:_dialog];
        /* only a Premium account may write custom emoji, so the tab waits for the answer about the signed in user */
        NoshiWeakReference *weak = _weak;
        [self whenPremiumKnown:^(BOOL premium) {
            NoshiChatController *chat = weak.target;
            if (chat && premium) [chat->_panel enableCustomEmojiWithSession:chat->_session media:chat->_media];
        }];
    }
    return _panel;
}

- (void)inputBarDidTapPanelButton:(NoshiInputBar *)bar {
    [_bots emojiPanelWillChange];
    _panelShown = !_panelShown;
    bar.panelShown = _panelShown;
    UITextView *text = bar.textView;
    text.inputView = _panelShown ? [self panel] : nil;
    if ([text isFirstResponder]) [text reloadInputViews];
    else [text becomeFirstResponder];
}

/* the alert of the search took the focus from the field, and inputBarDidEndEditing put the panel away with it: the panel comes back on the emoji list, with the result of the search */
- (void)inputPanelDidCloseEmojiSearch:(NoshiInputPanel *)panel {
    (void)panel;
    if (!_panelShown) [self inputBarDidTapPanelButton:_input];
}

- (void)inputPanel:(NoshiInputPanel *)panel didPickEmoji:(NSString *)emoji {
    (void)panel;
    [_input insertEmoji:emoji];
}

- (void)inputPanel:(NoshiInputPanel *)panel didPickCustomEmoji:(NoshiCustomEmojiDocument *)emoji {
    (void)panel;
    [_input insertCustomEmoji:emoji.documentId alt:emoji.alt];
}

- (void)inputPanelDidTapBackspace:(NoshiInputPanel *)panel {
    (void)panel;
    [_input deleteBackwardFromPicker];
}

- (void)inputPanel:(NoshiInputPanel *)panel didPickSticker:(NoshiSticker *)sticker {
    (void)panel;
    [self sendSticker:sticker.media];
}

/* an animation goes out the way a sticker does: a document of the server, named by its reference */
- (void)inputPanel:(NoshiInputPanel *)panel didPickGif:(NoshiMedia *)gif {
    (void)panel;
    [self sendSticker:gif];
}

- (void)inputPanel:(NoshiInputPanel *)panel didPickInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId {
    (void)panel;
    NoshiWeakReference *weak = _weak;
    int32_t replyTo = _replyToId;
    [self cancelCompose];
    [_session sendInlineResult:result queryId:queryId toDialog:_dialog randomId:[self newRandomId] replyTo:replyTo completion:^(int32_t messageId, NSString *errorName) {
        (void)messageId;
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) { NoshiGiftAlert(nil, NoshiGiftErrorText(errorName)); return; }
        [chat fetchNewestAfterInlineSend];
    }];
}

/* a message that a bot sent for us has no pending copy on this screen, and the answer of the server for it did not bring it into the list: the newest page is asked for, so the
   message stands in the chat at once and not after the chat is opened again */
- (void)fetchNewestAfterInlineSend {
    if (_pinnedList || _window) return;
    NoshiWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog offsetId:0 addOffset:0 limit:20 completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!messages) {
            NSLog(@"noshigram: the newest messages of chat %lld were not fetched after an inline send: %@", chat->_dialog.peerId, errorName);
            return;
        }
        [chat->_people addEntriesFromDictionary:people];
        [chat mergeMessages:messages];
        chat->_stickToBottom = YES;
        [chat rebuildItems];
    }];
}

- (void)inputPanelDidTapCreateSticker:(NoshiInputPanel *)panel {
    (void)panel;
    [NoshiStickerMaker startWithSession:_session host:self done:nil];
}

#pragma mark loading

/* a chat with a person says so with a greeting to send; every other chat keeps the plain line */
- (void)ensureGreetingCard {
    if (_greeting) return;
    _greeting = [[NoshiGreetingView alloc] initWithMedia:_media];
    NoshiWeakReference *weak = _weak;
    _greeting.onSend = ^(NoshiSticker *sticker) {
        NoshiChatController *chat = weak.target;
        if (chat) [chat sendSticker:sticker.media];
    };
    [self.view addSubview:_greeting];
}

- (void)showEmptyState {
    BOOL person = _dialog.kind == NOSHI_DIALOG_USER && !_dialog.saved && !_pinnedList;
    /* a bot's empty chat has its card and the start button instead */
    if (_dialog.kind == NOSHI_DIALOG_BOT && !_pinnedList) {
        [self showStatus:@"" retry:NO];
        return;
    }
    /* the saved messages show what the storage is for, and the duck is only looked at, not sent */
    if (_dialog.saved && !_pinnedList) {
        [self showStatus:@"" retry:NO];
        [self ensureGreetingCard];
        if (_greetingAsked) return;
        _greetingAsked = YES;
        [_greeting showSavedCard];
        NoshiWeakReference *weak = _weak;
        [_session loadStickersWithEmoticon:"\xf0\x9f\xa6\x86" completion:^(NSArray *stickers, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat) return;
            if (!stickers) {
                NSLog(@"noshigram: saved sticker did not load: %@", errorName);
                return;
            }
            [chat->_greeting showStickers:stickers];
        }];
        return;
    }
    if (!person) {
        [self showStatus:NSLocalizedString(@"chat.empty", nil) retry:NO];
        return;
    }
    [self showStatus:@"" retry:NO];
    [self ensureGreetingCard];
    if (_greetingAsked) return;
    _greetingAsked = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadGreetingStickers:^(NSArray *stickers, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!stickers) {
            NSLog(@"noshigram: greeting stickers did not load: %@", errorName);
            return;
        }
        [chat->_greeting showStickers:stickers];
    }];
    /* a person who wrote their own message for new chats shows it instead of the stock words */
    [_session loadFullUserOfDialog:_dialog completion:^(NoshiFullUser *user, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!user) {
            NSLog(@"noshigram: chat intro did not load: %@", errorName);
            return;
        }
        if (!user.hasIntro) return;
        [chat->_greeting showIntroTitle:user.introTitle text:user.introText sticker:user.introSticker author:chat->_dialog.title];
        [chat.view setNeedsLayout];
    }];
}

/* a person who takes messages only from Premium users closes the input of anyone who is not one: the card says why, and the bar says it in a line */
- (void)loadPremiumGate {
    if (_dialog.kind != NOSHI_DIALOG_USER || _dialog.saved) return;
    NoshiWeakReference *weak = _weak;
    [_session loadPremiumGateOfDialog:_dialog completion:^(BOOL blocked) {
        NoshiChatController *chat = weak.target;
        if (!chat || !blocked || chat->_premiumGate) return;
        chat->_premiumGate = [[NoshiPremiumGateView alloc] initWithName:chat->_dialog.title];
        [chat.view addSubview:chat->_premiumGate];
        chat->_input.writable = NO;
        chat->_input.readOnlyNote = [NSString stringWithFormat:NSLocalizedString(@"chat.premium.note", nil), chat->_dialog.title];
        [chat.view setNeedsLayout];
    }];
}

- (void)showStatus:(NSString *)text retry:(BOOL)retry {
    _status.text = text;
    _status.hidden = text.length == 0;
    _retry.hidden = !retry;
    [self.view setNeedsLayout];
}

- (void)loadNewest {
    if (_pinnedList) {
        if (!_loading) [self loadPinnedList];
        return;
    }
    if (_loading) return;
    _loading = YES;
    [self showStatus:nil retry:NO];
    NoshiWeakReference *weak = _weak;
    /* the place the person left the chat at comes back, as in the official clients; unread messages, a link and a bookmark take the opening first */
    BOOL restoreOnce = !_scrollRestoreChecked;
    _scrollRestoreChecked = YES;
    if (restoreOnce && _startMessageId <= 0 && !_openUnread && !_pinnedList && _dialog.unreadCount <= 0) {
        int32_t kept = [self keptScrollMessageId];
        if (kept > 0) {
            _startMessageId = kept;
            _restoringScroll = YES;
        }
    }
    if (_openUnread && !_pinnedList && _startMessageId <= 0) {
        _opening = YES;
        int32_t anchor = _unreadAnchor;
        [_session loadHistoryOfDialog:_dialog offsetId:anchor + 1 addOffset:-(HISTORY_PAGE / 2) limit:HISTORY_PAGE pageCompletion:^(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat) return;
            chat->_loading = NO;
            if (!messages) {
                chat->_opening = NO;
                [chat showStatus:[chat failureTextForError:errorName] retry:YES];
                return;
            }
            if (!messages.count) {
                chat->_openUnread = NO;
                [chat loadNewest];
                return;
            }
            chat->_openUnread = NO;
            chat->_loadedFirst = YES;
            [chat enterWindowWithMessages:messages people:people page:page];
            [chat->_table layoutIfNeeded];
            for (NSUInteger i = 0; i < chat->_items.count; ++i) {
                NoshiChatItem *item = [chat->_items objectAtIndex:i];
                BOOL unread = !item.message.outgoing && item.message.messageId > anchor;
                for (NoshiMessage *part in item.albumMessages) if (!part.outgoing && part.messageId > anchor) unread = YES;
                if (unread) {
                    [chat->_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
                    break;
                }
            }
            chat->_table.hidden = NO;
            chat->_opening = NO;
            [chat startWatchingHistory];
            [chat markReadIfNeeded];
            CGFloat distance = chat->_table.contentSize.height - chat->_table.contentOffset.y - chat->_table.bounds.size.height + chat->_table.contentInset.bottom;
            [chat loadNewerIfNeeded:distance];
            [chat pollReactions];
        }];
        return;
    }
    _openUnread = NO;
    /* the page kept on disk shows while the network works, and stays if the network fails */
    [_session loadCachedHistoryOfDialog:_dialog completion:^(NSArray *kept, NSDictionary *people, NSString *errorName) {
        (void)errorName;
        NoshiChatController *chat = weak.target;
        if (chat) [chat showKeptMessages:kept people:people];
    }];
    [_session loadHistoryOfDialog:_dialog offsetId:0 addOffset:0 limit:HISTORY_PAGE pageCompletion:^(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat didLoadNewest:messages people:people page:page error:errorName];
    }];
}

- (NSString *)failureTextForError:(NSString *)name {
    if ([name isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    if ([name isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), name];
}

- (void)showKeptMessages:(NSArray *)kept people:(NSDictionary *)people {
    if (!kept.count || _loadedFirst || _server.count) return;
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:kept];
    [self rebuildItems];
    if (_startMessageId > 0 && _restoringScroll) {
        /* the place the person left the chat at: the list that is shown from its top and moved to the place when the network answers was seen scrolling up first. the kept page
           goes straight to the place when it holds it, and when it does not the list stays hidden until the answer finds it */
        int32_t place = _startMessageId;
        BOOL held = NO;
        for (NoshiChatItem *item in _items) if (item.message.messageId == place) { held = YES; break; }
        if (!held) return;
        _startMessageId = 0;
        [self restoreScrollToMessageId:place];
    } else if (_stickToBottom && _startMessageId <= 0) {
        [self scrollToBottomAnimated:NO];
    }
    _table.hidden = NO;
    /* a network failure can arrive before the cached page */
    [self showStatus:nil retry:NO];
}

/* whether the id is that of a post at the head of the thread of comments this chat shows */
- (BOOL)isDiscussionRootId:(int32_t)messageId {
    if (!_dialog.discussion || messageId <= 0) return NO;
    for (NoshiMessage *root in _dialog.discussionMessages) {
        if (root.messageId == messageId) return YES;
    }
    return NO;
}

- (void)mergeDiscussionMessagesAtHistoryEnd {
    if (_canLoadMore || !_dialog.discussionMessages.count) return;
    [_people addEntriesFromDictionary:_dialog.discussionPeople];
    for (NoshiMessage *root in _dialog.discussionMessages)
        if (![_server objectForKey:[NSNumber numberWithInt:root.messageId]]) [self mergeMessages:[NSArray arrayWithObject:root]];
}

- (void)didLoadNewest:(NSArray *)messages people:(NSDictionary *)people page:(noshi_history_page)page error:(NSString *)errorName {
    _loading = NO;
    if (!messages && _server.count) {
        NSLog(@"noshigram: chat %lld stays on the kept page, refresh failed: %@", _dialog.peerId, errorName);
        _opening = NO;
        return;
    }
    if (!messages) {
        _opening = NO;
        [self showStatus:[self failureTextForError:errorName] retry:YES];
        return;
    }
    _loadedFirst = YES;
    int more = 0;
    if (noshi_history_cursor_advance(0, &page, HISTORY_PAGE, &_historyOldestId, &more) != NOSHI_OK)
        NSLog(@"noshigram: invalid newest history page for chat %lld", _dialog.peerId);
    if (page.oldest_id > 0) {
        for (NSNumber *key in [_server allKeys]) {
            if (key.intValue < page.oldest_id) [_server removeObjectForKey:key];
        }
    }
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:messages];
    _canLoadMore = more;
    [self mergeDiscussionMessagesAtHistoryEnd];
    if (!_server.count) [self showEmptyState];
    [self rebuildItems];
    /* the list that followed its end already stands on it; this makes sure of the position once the real sizes are in, before anything may animate */
    if (_stickToBottom && _startMessageId <= 0) [self scrollToBottomAnimated:NO];
    _table.hidden = NO;
    _opening = NO;
    if (_startMessageId > 0) {
        /* a bookmark opened this chat: it goes to its message, loading older pages when that one is not in the newest */
        int32_t target = _startMessageId;
        _startMessageId = 0;
        if (_restoringScroll) [self restoreScrollToMessageId:target];
        else [self jumpToMessageId:target];
    }
    [self markReadIfNeeded];
    [self startWatchingHistory];
    [self pollReactions];
}

- (void)startWatchingHistory {
    NoshiWeakReference *weak = _weak;
    [_session watchDialog:_dialog owner:self peopleHandler:^(NSArray *page, NSDictionary *people) {
        NoshiChatController *chat = weak.target;
        if (chat) {
            [chat->_people addEntriesFromDictionary:people];
            [chat storeDidChange:page];
        }
    }];
}

- (void)loadOlder {
    /* the offset a list passes through while it settles on the newest message would ask for older rows, which then move it again */
    if (_loadingOlder || _olderDeferred || !_canLoadMore || !_loadedFirst || _opening || _historyOldestId <= 1) return;
    _loadingOlder = YES;
    NSUInteger token = _windowToken;
    NoshiWeakReference *weak = _weak;
    int32_t before = _historyOldestId;
    [_session loadHistoryOfDialog:_dialog offsetId:before addOffset:0 limit:OLDER_PAGE pageCompletion:^(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        /* a page asked for before the list moved to another stretch of history belongs to the old one */
        if (!chat || token != chat->_windowToken) return;
        [chat didLoadOlder:messages people:people page:page before:before error:errorName];
    }];
}

- (void)didLoadOlder:(NSArray *)messages people:(NSDictionary *)people page:(noshi_history_page)page before:(int32_t)before error:(NSString *)errorName {
    _loadingOlder = NO;
    if (!messages) {
        /* the list stays as it is and the next scroll to the top asks again */
        NSLog(@"noshigram: older messages of chat %lld not loaded: %@", _dialog.peerId, errorName);
        return;
    }
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:messages];
    int more = 0;
    if (noshi_history_cursor_advance(before, &page, OLDER_PAGE, &_historyOldestId, &more) != NOSHI_OK)
        NSLog(@"noshigram: history of chat %lld did not advance before %d", _dialog.peerId, (int)before);
    _canLoadMore = more;
    [self mergeDiscussionMessagesAtHistoryEnd];
    /* putting rows above the ones in view moves the offset, and moving the offset ends the momentum of a swipe */
    if (_table.dragging || _table.decelerating) {
        _olderDeferred = YES;
        return;
    }
    [self showOlder];
}

- (void)showOlder {
    _olderDeferred = NO;
    [self rebuildItems];
    [self scrollToTargetOrLoadMore];
}

/* the live page of the store: it is the truth for the ids it spans, so a message of those ids that is missing from it was
   deleted, and what it holds replaces what is here */
- (void)storeDidChange:(NSArray *)page {
    if (!_loadedFirst || !page.count) return;
    if (_window) {
        /* the live page of the store is the end of the chat, which a window around an old message is not next to: only a change of a message the window holds
           is taken, so edits and reactions show while the new messages wait for the list to reach them */
        NSMutableArray *held = [NSMutableArray array];
        for (NoshiMessage *message in page) if ([_server objectForKey:[NSNumber numberWithInt:message.messageId]]) [held addObject:message];
        if (held.count) {
            [self mergeMessages:held];
            [self scheduleLiveMessages];
        }
        return;
    }
    if (_canLoadMore && _historyOldestId > 0) {
        NSMutableArray *contiguous = [NSMutableArray array];
        for (NoshiMessage *message in page) if (message.messageId >= _historyOldestId) [contiguous addObject:message];
        page = contiguous;
        if (!page.count) return;
    }
    int32_t lowest = INT32_MAX;
    NSMutableSet *present = [NSMutableSet set];
    for (NoshiMessage *message in page) {
        lowest = MIN(lowest, message.messageId);
        [present addObject:[NSNumber numberWithInt:message.messageId]];
    }
    /* a message is gone when the store held it and holds it no more */
    NSMutableArray *missing = [NSMutableArray array];
    for (NSNumber *key in _storeIds) {
        if ([key intValue] >= lowest && ![present containsObject:key] && [_server objectForKey:key]) [missing addObject:key];
    }
    /* a page read in the middle of a burst of writes can lack a message that is there a moment later, and a message dropped on that word alone vanished from the
       screen in a spam; the server is asked, and only what it does not have any more goes */
    [self confirmGoneMessages:missing];
    if (!_storeIds) _storeIds = [[NSMutableSet alloc] init];
    [_storeIds setSet:present];
    int32_t knownTop = 0;
    for (NSNumber *key in [_server allKeys]) knownTop = MAX(knownTop, [key intValue]);
    [self mergeMessages:page];
    BOOL newest = NO, arrived = NO, pinChanged = NO;
    /* who wrote the newest message that came in, for the tone that person has of their own */
    int32_t arrivedId = 0;
    for (NoshiMessage *message in page) {
        /* somebody pinned a message: the bar at the top was made when the chat opened, so it is made again */
        if (message.messageId > knownTop && message.service == (int)NOSHI_SERVICE_PIN + 1) pinChanged = YES;
        if (message.messageId > _markedRead && !message.outgoing) newest = YES;
        /* only a message past everything the screen held is news, so a refresh of the page makes no sound */
        /* an effect plays for a message that comes in while the chat is open, as it does when the other side sends one */
        if (message.messageId > knownTop && !message.outgoing && message.effectId) [self playMessageEffect:message.effectId];
        if (message.messageId > knownTop && !message.outgoing) {
            arrived = YES;
            if (message.messageId > arrivedId) arrivedId = message.messageId;
        }
    }
    [self scheduleLiveMessages];
    if (pinChanged && !_pinnedList) {
        if (_dialog.peerKind == 3) [self loadChannelFull];
        else [self loadTopicPinned];
    }
    if (newest) {
        [self markReadIfNeeded];
    }
    if (arrived && _visible && !_voice) NoshiPlayInChatSound(YES);
}

/* asks the server for messages the store stopped showing; a failed ask leaves the list as it is */
- (void)confirmGoneMessages:(NSArray *)ids {
    if (!ids.count) return;
    if (!_confirmingGone) _confirmingGone = [[NSMutableSet alloc] init];
    NSMutableArray *asked = [NSMutableArray array];
    for (NSNumber *key in ids) {
        if ([_confirmingGone containsObject:key] || asked.count >= 100) continue;
        [asked addObject:key];
        [_confirmingGone addObject:key];
    }
    if (!asked.count) return;
    NoshiWeakReference *weak = _weak;
    [_session loadMessagesWithIds:asked ofDialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        for (NSNumber *key in asked) [chat->_confirmingGone removeObject:key];
        if (!messages) {
            NSLog(@"noshigram: the messages missing from the store were not confirmed: %@", errorName);
            return;
        }
        NSMutableSet *held = [NSMutableSet set];
        for (NoshiMessage *message in messages) [held addObject:[NSNumber numberWithInt:message.messageId]];
        for (NSNumber *key in asked) if (![held containsObject:key]) [chat->_server removeObjectForKey:key];
        [chat mergeMessages:messages];
        [chat scheduleLiveMessages];
    }];
}

- (void)messageCell:(NoshiMessageCell *)cell answerSharingRequest:(BOOL)accept {
    NoshiMessage *message = cell.item.message;
    if (message.service != NOSHI_SERVICE_SHARING_REQUEST + 1 || message.outgoing || [self sharingExpired:message] || message.messageId <= 0) return;
    NSNumber *key = [NSNumber numberWithInt:message.messageId];
    if ([_sharingBusy containsObject:key]) return;
    BOOL restricted = accept ? (message.serviceValue & 2) != 0 : (message.serviceValue & 1) != 0;
    NoshiWeakReference *weak = _weak;
    NoshiConfirm(nil, NSLocalizedString(accept ? @"chat.sharing.accept.confirm" : @"chat.sharing.decline.confirm", nil),
                   NSLocalizedString(accept ? @"chat.sharing.accept" : @"chat.sharing.decline", nil), ^{
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if ([chat sharingExpired:message]) { [chat rebuildItems]; return; }
        if (!chat->_sharingBusy) chat->_sharingBusy = [[NSMutableSet alloc] init];
        if ([chat->_sharingBusy containsObject:key]) return;
        [chat->_sharingBusy addObject:key];
        [chat->_session setSharingRestricted:restricted ofDialog:chat->_dialog requestId:key.intValue completion:^(NSString *errorName) {
            NoshiChatController *current = weak.target;
            if (!current) return;
            [current->_sharingBusy removeObject:key];
            if (errorName) {
                NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.sharing.error", nil), errorName]);
                return;
            }
            [current->_session loadMessagesWithIds:[NSArray arrayWithObject:key] ofDialog:current->_dialog completion:^(NSArray *messages, NSString *error) {
                NoshiChatController *owner = weak.target;
                if (!owner) return;
                if (error) { NoshiShowNotice(nil, [owner failureTextForError:error]); return; }
                [owner mergeMessages:messages];
                [owner scheduleLiveMessages];
            }];
        }];
    });
}

/* a burst of updates shares one table transaction per frame; a drag keeps its rows until the finger settles */
- (void)scheduleLiveMessages {
    _livePending = YES;
    if (_liveLink || !_visible || _interacting || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NoshiReactionPollTarget *target = [[[NoshiReactionPollTarget alloc] initWithReference:_weak] autorelease];
    _liveLink = [[CADisplayLink displayLinkWithTarget:target selector:@selector(display:)] retain];
    NoshiSetFrameRate(_liveLink, 30);
    [_liveLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

/* a rebuild walks every loaded message, so in a group with a long history it costs tens of milliseconds on an old phone, and a burst of messages asked for one at every frame.
   the next one waits three times as long as the last took, which holds the rebuilds to a quarter of the main thread and is no wait at all for a short chat */
#define REBUILD_WAIT_FACTOR 3.0

- (void)flushLiveMessages {
    if ([self replySwipeActive]) return;
    if (_livePending && _visible && !_interacting && [UIApplication sharedApplication].applicationState == UIApplicationStateActive &&
        CACurrentMediaTime() - _rebuildEndedAt < _rebuildCost * REBUILD_WAIT_FACTOR) {
        /* called by hand (the screen came back) there is no link running, and the wait would lose the rebuild */
        [self scheduleLiveMessages];
        return;
    }
    [_liveLink invalidate];
    [_liveLink release];
    _liveLink = nil;
    if (!_livePending || _interacting || !_visible || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    _livePending = NO;
    [self rebuildItems];
}

/* a message of the favorites with no origin in its answer is one of the account's own notes */
- (BOOL)message:(NoshiMessage *)message isFromSavedSource:(NoshiDialog *)source {
    if (!message.savedPeerKind) return source.saved;
    return message.savedPeerKind == source.peerKind && message.savedPeerId == source.peerId;
}

/* the server does not say when a voice note of somebody else was played, so the phone keeps that time itself, for the ring of the note and for its details */
static NSString *const NoshiListenedKey = @"noshigram.voice.listened";
#define LISTENED_KEPT_MAX 400

- (NSString *)listenedKeyOfMessageId:(int32_t)messageId {
    return [NSString stringWithFormat:@"%d:%lld:%d", (int)_dialog.peerKind, _dialog.peerId, (int)messageId];
}

- (void)restoreListenedOfMessage:(NoshiMessage *)message {
    if (message.outgoing || message.media.kind != NOSHI_PREVIEW_VOICE) return;
    NSNumber *at = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiListenedKey] objectForKey:[self listenedKeyOfMessageId:message.messageId]];
    if (!at) return;
    message.listenedDate = [NSDate dateWithTimeIntervalSince1970:[at doubleValue]];
    message.mediaUnread = NO;
}

- (void)rememberListenedMessageId:(int32_t)messageId {
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiListenedKey]];
    NSString *key = [self listenedKeyOfMessageId:messageId];
    if ([all objectForKey:key]) return;
    [all setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:key];
    while (all.count > LISTENED_KEPT_MAX) {
        NSString *oldest = nil;
        double oldestAt = 0;
        for (NSString *candidate in all) {
            double at = [[all objectForKey:candidate] doubleValue];
            if (!oldest || at < oldestAt) { oldest = candidate; oldestAt = at; }
        }
        [all removeObjectForKey:oldest];
    }
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:NoshiListenedKey];
}

/* a note of somebody else that starts playing is heard: the other side is told at once, as the official clients do, unless the person reads in secret, and the ring of the
   note goes faint. The phone keeps the time either way */
- (void)voicePlayerChanged:(NSNotification *)note {
    (void)note;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    NoshiMedia *track = player.track;
    if (!track || track.kind != NOSHI_PREVIEW_VOICE || track.viewOnce || player.state != NoshiMusicStatePlaying) return;
    for (NoshiChatItem *item in _items) {
        NoshiMessage *message = item.message;
        if (message.outgoing || message.messageId <= 0 || message.listenedDate || message.media.kind != NOSHI_PREVIEW_VOICE || ![message.media.file.key isEqualToString:track.file.key]) continue;
        [self rememberListenedMessageId:message.messageId];
        message.listenedDate = [NSDate date];
        BOOL told = message.mediaUnread;
        message.mediaUnread = NO;
        if (told) {
            [_session markContentsRead:[NSArray arrayWithObject:[NSNumber numberWithInt:message.messageId]] dialog:_dialog completion:^(NSString *errorName) {
                if (errorName && ![errorName isEqualToString:@"NOT_SENT"]) NSLog(@"noshigram: the server was not told that a voice note was heard: %@", errorName);
            }];
        }
        [self scheduleLiveMessages];
        return;
    }
}

- (void)keepUploadedMediaOf:(NoshiMessage *)local server:(NoshiMessage *)server {
    NoshiOutgoing *sent = local.pendingSend;
    /* the server makes the thumbnail of a video some moments after the send, and the copy that replaces the pending one has none until then */
    if (sent && sent->kind == NoshiOutgoingVideo && sent->preview && server.messageId > 0) {
        if (!_posters) _posters = [[NSMutableDictionary alloc] init];
        [_posters setObject:sent->preview forKey:[NSNumber numberWithInt:server.messageId]];
        server.localPoster = sent->preview;
    }
    if (!sent || !sent->path || sent->viewOnce || sent->kind == NoshiOutgoingPhoto) return;
    noshi_media_ref ref = server.media.ref;
    if (ref.source != NOSHI_MEDIA_SOURCE_DOCUMENT || !server.media.file) {
        if (sent->temporary) [[NSFileManager defaultManager] removeItemAtPath:sent->path error:NULL];
        return;
    }
    NoshiWeakReference *weak = _weak;
    [_media cacheUploadedPath:sent->path forFile:server.media.file size:server.media.size temporary:sent->temporary completion:^(BOOL stored) {
        NoshiChatController *chat = weak.target;
        if (stored && chat) [chat->_table reloadData];
    }];
}

- (void)mergeMessages:(NSArray *)messages {
    [_media noteMessages:messages ofDialog:_dialog];
    for (NoshiMessage *message in messages) {
        if (message.messageId <= 0) continue;
        [self restoreListenedOfMessage:message];
        if (_dialog.saved) [message placeInSavedMessagesOfUser:_dialog.peerId];
        if (_dialog.savedSource && ![self message:message isFromSavedSource:_dialog.savedSource]) continue;
        [_server setObject:message forKey:[NSNumber numberWithInt:message.messageId]];
        UIImage *poster = [_posters objectForKey:[NSNumber numberWithInt:message.messageId]];
        if (poster) message.localPoster = poster;
    }
    /* a message sent from here is replaced by the server's copy of it as soon as that arrives */
    for (NoshiMessage *local in [[_local copy] autorelease]) {
        NoshiMessage *server = local.messageId > 0 ? [_server objectForKey:[NSNumber numberWithInt:local.messageId]] : nil;
        if (server) {
            [self keepUploadedMediaOf:local server:server];
            [_local removeObject:local];
            _localReplaced = YES;
        }
    }
}

- (void)markReadIfNeeded {
    if (!_visible || !_loadedFirst || _opening || _loadingWindow || _scrollTarget > 0 || _jumpLink || _pinnedList) return;
    [self scheduleVisibleMentionsRead];
    [self scheduleVisibleReactionsRead];
    int32_t newest = 0;
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)path.row];
        NoshiMessage *message = item.message;
        /* a message of ours counts as well: whoever wrote has seen all that stands before it, and the server takes the mark up to it as read. with only incoming ones counted, a chat whose
           screen showed nothing but our own words, after the answer, never said anything of what it had shown above, and the count of the row stayed */
        if (message.messageId > newest) newest = message.messageId;
        for (NoshiMessage *part in item.albumMessages) if (part.messageId > newest) newest = part.messageId;
    }
    if (newest <= _markedRead || newest <= _dialog.readInboxMaxId || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    int32_t before = _markedRead;
    _markedRead = newest;
    /* the end of the chat is in view when the history has nothing newer to load and the last row is on the screen, so no message is left unread beyond the one marked */
    NSUInteger last = _items.count ? _items.count - 1 : NSNotFound;
    BOOL toEnd = !_window && !_canLoadNewer && last != NSNotFound && [[_table indexPathsForVisibleRows] containsObject:[NSIndexPath indexPathForRow:(NSInteger)last inSection:0]];
    NoshiWeakReference *weak = _weak;
    [_session markDialogRead:_dialog upTo:newest toEnd:toEnd completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            /* the mark did not reach the server, so the next time the end comes into view says it again, instead of waiting for a newer message */
            if (chat->_markedRead == newest) chat->_markedRead = before;
            return;
        }
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:chat->_dialog.peerKind], @"kind", [NSNumber numberWithLongLong:chat->_dialog.peerId], @"peer",
                              [NSNumber numberWithInt:chat->_dialog.topicId], @"topic", [NSNumber numberWithInt:newest], @"maxId", [NSNumber numberWithBool:toEnd], @"toEnd", nil];
        NoshiDialogsApplyingRead([NSArray arrayWithObject:chat->_dialog], info);
    }];
}

/* "3 reactions" and the first three who reacted; a tap opens the whole list. the faces come from the first page of that list, which the page asks for again when it opens */
- (void)fillReactorsLineOfMenu:(NoshiMessageMenu *)menu message:(NoshiMessage *)message {
    NSInteger total = 0;
    for (NoshiReaction *reaction in message.reactions) total += reaction.count;
    if (total <= 0) return;
    NoshiWeakReference *weak = _weak;
    int32_t messageId = message.messageId;
    [menu setReactorsText:[NSString stringWithFormat:NSLocalizedString([@"chat.msg.reactions." stringByAppendingString:NoshiPluralForm(total)], nil), (int)total]];
    menu.reactorsHandler = ^{
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        NoshiReactionPeopleController *page = [[[NoshiReactionPeopleController alloc] initWithSession:chat->_session dialog:chat->_dialog messageId:messageId avatars:chat->_avatars media:chat->_media] autorelease];
        [chat.navigationController pushViewController:page animated:YES];
    };
    NoshiMessageMenu *shown = menu;
    [_session loadReactorsOfMessageId:messageId ofDialog:_dialog offset:nil completion:^(NSArray *items, NSDictionary *people, NSString *next, NSString *errorName) {
        (void)next;
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) { NSLog(@"noshigram: the first reactors of message %d could not be loaded: %@", (int)messageId, errorName); return; }
        NSMutableArray *faces = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *entry in items) {
            NSNumber *key = [entry objectForKey:@"peer"];
            if (!key || [seen containsObject:key]) continue;
            [seen addObject:key];
            NoshiPerson *person = [people objectForKey:key];
            if (!person) person = [chat->_people objectForKey:key];
            if (person) [faces addObject:person];
            if (faces.count == 3) break;
        }
        [shown setReactorsPeople:faces cache:chat->_avatars];
    }];
}

- (void)scheduleVisibleMentionsRead {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markVisibleMentionsRead) object:nil];
    [self performSelector:@selector(markVisibleMentionsRead) withObject:nil afterDelay:0];
}

- (void)markVisibleMentionsRead {
    if (!_visible || _pinnedList || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        NoshiMessage *message = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if (!message.unreadMention || message.outgoing || message.messageId <= 0 || [_readMentionIds containsObject:key]) continue;
        [ids addObject:key];
        [_readMentionIds addObject:key];
        if (ids.count == NOSHI_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    NoshiWeakReference *weak = _weak;
    [_session markMentionsRead:ids dialog:_dialog completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) [chat->_readMentionIds minusSet:[NSSet setWithArray:ids]];
        else [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
    }];
}

#pragma mark items

typedef struct { int64_t key; NSUInteger index; } NoshiMessageOrder;

/* the index breaks a tie, so two messages with one id keep the order they were collected in */
static int NoshiCompareMessageOrder(const void *first, const void *second) {
    const NoshiMessageOrder *a = first, *b = second;
    if (a->key != b->key) return a->key < b->key ? -1 : 1;
    return a->index < b->index ? -1 : (a->index > b->index);
}

/* the answer of a send carries the server's copy of the message before the call that numbers the pending one is told, so for a moment the chat
   holds both; the pending one is left out while a copy of it (ours, same words, written at the same time) is already there */
- (NSArray *)localWithoutServerTwins {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_local.count];
    NSMutableSet *claimed = [NSMutableSet set];
    NSArray *held = nil;
    for (NoshiMessage *pending in _local) {
        BOOL twin = NO;
        if (pending.messageId <= 0 && pending.state != NoshiMessageStateFailed) {
            /* one copy of the list for all the pending messages, and none when nothing is pending */
            if (!held) held = [_server allValues];
            for (NoshiMessage *copy in held) {
                NSNumber *key = [NSNumber numberWithInt:copy.messageId];
                if (!copy.outgoing || [claimed containsObject:key]) continue;
                if (copy.date < pending.date - 2 || copy.date > pending.date + 120) continue;
                /* a message that was in the chat before this one was written is not its copy, however alike the words are: sending the same words twice hid the second
                   until it was numbered, and then it came back */
                if (copy.messageId <= pending.sentAfterId) continue;
                if (pending.text != copy.text && ![pending.text isEqualToString:copy.text]) continue;
                [claimed addObject:key];
                twin = YES;
                break;
            }
        }
        if (!twin) [kept addObject:pending];
    }
    return kept;
}

/* the server's messages and the ones only this screen knows, in the order the chat has them: by id, and a message that has
   no id yet after all of those, in the order it was written */
- (NSArray *)orderedMessages {
    NSArray *server = [_server allValues];
    /* a message on its way belongs to the end of the chat, which a window around an old message does not show */
    NSArray *local = _window ? [NSArray array] : [self localWithoutServerTwins];
    NSUInteger count = server.count + local.count;
    NoshiMessageOrder *order = malloc(sizeof(NoshiMessageOrder) * (count ? count : 1));
    NSMutableArray *all = [NSMutableArray arrayWithCapacity:count];
    if (!order) {
        NSLog(@"noshigram: no memory to order %lu messages", (unsigned long)count);
        return all;
    }
    [all addObjectsFromArray:server];
    [all addObjectsFromArray:local];
    for (NSUInteger i = 0; i < count; ++i) {
        NoshiMessage *message = [all objectAtIndex:i];
        order[i].index = i;
        order[i].key = message.messageId > 0 ? message.messageId : INT64_MAX / 2 + (int64_t)(i - server.count);
    }
    qsort(order, count, sizeof(*order), NoshiCompareMessageOrder);
    NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; ++i) {
        [sorted addObject:[all objectAtIndex:order[i].index]];
    }
    free(order);
    return sorted;
}

/* a pending message keeps its random id after the server numbers it; a clash between the two spaces only costs a rebuild,
   since reflectsMessage: compares both ids */
- (NSNumber *)cacheKeyForMessage:(NoshiMessage *)message {
    return [NSNumber numberWithLongLong:message.randomId ? message.randomId : (long long)message.messageId];
}

/* one number per calendar day. the components call costs tens of microseconds on an old phone and a rebuild asks it twice for every message, so the span of the day that was
   asked last is kept: messages come in the order of their ids, which is the order of their dates, and all but the first of a day are answered by two compares */
typedef struct { int32_t from; int32_t to; NSInteger key; } NoshiDaySpan;

static NSInteger NoshiDayKey(NSCalendar *calendar, int32_t date, NoshiDaySpan *span) {
    if (span->to > span->from && date >= span->from && date < span->to) return span->key;
    NSDate *moment = [NSDate dateWithTimeIntervalSince1970:date];
    NSDateComponents *parts = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:moment];
    NSInteger key = parts.year * 10000 + parts.month * 100 + parts.day;
    NSDate *start = nil;
    NSTimeInterval length = 0;
    span->from = span->to = 0;
    if ([calendar rangeOfUnit:NSDayCalendarUnit startDate:&start interval:&length forDate:moment] && start && length > 0) {
        NSTimeInterval from = [start timeIntervalSince1970], to = from + length;
        if (from >= INT32_MIN && to <= INT32_MAX && date >= from && date < to) {
            span->from = (int32_t)from;
            span->to = (int32_t)to;
            span->key = key;
        }
    }
    return key;
}

/* two messages share a run when the same side wrote both within a few minutes of each other on one day */
- (BOOL)message:(NoshiMessage *)a joins:(NoshiMessage *)b {
    if (a.service || b.service || a.outgoing != b.outgoing || a.senderKey != b.senderKey) return NO;
    int32_t gap = a.date > b.date ? a.date - b.date : b.date - a.date;
    return gap < GROUP_GAP_SECONDS;
}

/* custom emoji in the texts and the custom reactions on the messages; their pictures are fetched once, and the
   ordinary emoji each stands for is what a reaction chip shows until its picture is in memory */
/* the name of a private chat is followed by the custom emoji status of the other side, or the Premium star; the picture is fetched once
   and the title is drawn again when it lands */
/* the ids of the developers arrive after the screen is up: the hammers of the title and of the names in the bubbles are decided again */
/* what the dialog said when it was listed, or what an update told since */
- (int32_t)readOutboxMaxId {
    return MAX(_dialog.readOutboxMaxId, [_session readOutboxOfKind:_dialog.peerKind peer:_dialog.peerId topic:_dialog.topicId]);
}

/* the dialog is a snapshot from when the chat opened, so a person who comes online while it is open would keep the old last seen time until the chat is reopened */
- (void)userStatusChanged:(NSNotification *)note {
    if (_dialog.kind != NOSHI_DIALOG_USER || _dialog.saved || _dialog.peerKind != 1) return;
    if ([[note.userInfo objectForKey:@"user"] longLongValue] != _dialog.peerId) return;
    [_dialog setPresence:(noshi_presence)[[note.userInfo objectForKey:@"presence"] intValue] seen:[[note.userInfo objectForKey:@"seen"] intValue]];
    [self refreshStatusLine];
}

- (void)readOutboxChanged:(NSNotification *)note {
    if ([[note.userInfo objectForKey:@"kind"] intValue] != _dialog.peerKind || [[note.userInfo objectForKey:@"peer"] longLongValue] != _dialog.peerId) return;
    if ([[note.userInfo objectForKey:@"topic"] intValue] != _dialog.topicId) return;
    /* every read of a busy group moves this number */
    if (_loadedFirst) [self scheduleLiveMessages];
}

/* the ring on the cross of a message that is going up; the row is touched in place, since a rebuild of the list for every part of a file would redraw the screen */
- (void)uploadProgressed:(NSNotification *)note {
    long long randomId = [[note.userInfo objectForKey:@"randomId"] longLongValue];
    float fraction = [[note.userInfo objectForKey:@"fraction"] floatValue];
    for (NoshiMessage *message in _local) {
        if (message.randomId != randomId) continue;
        message.uploadProgress = fraction;
        for (NoshiMessageCell *cell in _table.visibleCells) {
            if ([cell isKindOfClass:[NoshiMessageCell class]] && cell.item.message == message) [cell showUploadProgress];
        }
        return;
    }
}


- (void)showTitleBadge {
    long long badge = NoshiDialogBadgeDocument(_dialog);
    NSArray *entities = nil;
    _title.text = NoshiNameWithBadge(_dialog.title, badge, &entities);
    _title.entities = entities;
    if (!_dialog.emojiStatus) return;
    NoshiWeakReference *weak = _weak;
    NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:_dialog.emojiStatus]], _session, _media, ^{
        NoshiChatController *chat = weak.target;
        if (chat) [chat->_title setNeedsDisplay];
    });
}

/* the rows laid out before the words of a custom emoji were known are laid out again; every other row keeps its layout, where a flush of the whole cache made a chat of
   thousands of messages measure all of them again each time a batch of emoji arrived */
- (void)dropItemsWearingDocuments:(NSDictionary *)documents {
    NSMutableArray *stale = [NSMutableArray array];
    [_itemCache enumerateKeysAndObjectsUsingBlock:^(id key, NoshiChatItem *item, BOOL *stop) {
        (void)stop;
        for (NoshiTextEntity *entity in item.replyEntities) {
            if (entity.style == NoshiTextStyleCustomEmoji && [documents objectForKey:[NSNumber numberWithLongLong:entity.documentId]]) { [stale addObject:key]; return; }
        }
        NSMutableArray *messages = [NSMutableArray arrayWithObject:item.message ? item.message : (id)[NSNull null]];
        if (item.albumMessages.count) [messages addObjectsFromArray:item.albumMessages];
        for (id entry in messages) {
            if (![entry isKindOfClass:[NoshiMessage class]]) continue;
            NoshiMessage *message = entry;
            BOOL wears = NO;
            for (NoshiTextEntity *entity in message.entities) {
                if (entity.style == NoshiTextStyleCustomEmoji && [documents objectForKey:[NSNumber numberWithLongLong:entity.documentId]]) { wears = YES; break; }
            }
            for (NoshiReaction *reaction in message.reactions) {
                if (wears) break;
                if (reaction.row.kind == NOSHI_REACTION_CUSTOM && [documents objectForKey:[NSNumber numberWithLongLong:reaction.row.document_id]]) wears = YES;
            }
            if (wears) { [stale addObject:key]; break; }
        }
    }];
    [_itemCache removeObjectsForKeys:stale];
}

static void NoshiRedrawTree(UIView *view);

- (void)addCustomEmojiOfEntities:(NSArray *)entities to:(NSMutableArray *)wanted {
    for (NoshiTextEntity *entity in entities) {
        if (entity.style == NoshiTextStyleCustomEmoji && entity.documentId) [wanted addObject:[NSNumber numberWithLongLong:entity.documentId]];
    }
}

- (void)loadCustomEmoji {
    NSMutableArray *wanted = [NSMutableArray array];
    for (NoshiMessage *message in [_server allValues]) {
        [self addCustomEmojiOfEntities:message.entities to:wanted];
        /* the question and the answers of a poll carry their own entities, and the poll is drawn with the plain emoji they stand for until the pictures are here */
        if (message.poll) {
            [self addCustomEmojiOfEntities:message.poll.questionEntities to:wanted];
            for (NoshiPollAnswer *answer in message.poll.answers) [self addCustomEmojiOfEntities:answer.entities to:wanted];
        }
        for (NoshiReaction *reaction in message.reactions) {
            long long document = reaction.row.document_id;
            if (reaction.row.kind == NOSHI_REACTION_CUSTOM && document) [wanted addObject:[NSNumber numberWithLongLong:document]];
        }
    }
    /* the pinned messages are not among the loaded history, and the bar under the header shows the custom emoji of the one it holds */
    for (NoshiMessage *pinned in _pinnedAll) [self addCustomEmojiOfEntities:pinned.entities to:wanted];
    /* the statuses that follow the names of the people who wrote */
    for (NoshiPerson *person in [_people allValues]) {
        if (person.emojiStatus) [wanted addObject:[NSNumber numberWithLongLong:person.emojiStatus]];
    }
    if (!wanted.count) return;
    NoshiWeakReference *weak = _weak;
    [NoshiCustomEmojiLoader loadDocuments:wanted session:_session media:_media documents:^(NSArray *documents) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        NSMutableDictionary *texts = [NSMutableDictionary dictionaryWithCapacity:documents.count];
        for (NoshiCustomEmojiDocument *document in documents) [texts setObject:document.alt forKey:[NSNumber numberWithLongLong:document.documentId]];
        [NoshiReaction rememberCustomTexts:texts];
        [chat dropItemsWearingDocuments:texts];
        [chat scheduleLiveMessages];
    } picture:^{
        NoshiChatController *chat = weak.target;
        if (chat) { [chat redrawVisibleCells]; NoshiRedrawTree(chat->_pinnedBar); }
    }];
}

/* a picture that arrives changes no size, so the rows on screen are only drawn again */
static void NoshiRedrawTree(UIView *view) {
    [view setNeedsDisplay];
    for (UIView *child in view.subviews) NoshiRedrawTree(child);
}

- (void)redrawVisibleCells {
    for (UITableViewCell *cell in _table.visibleCells) NoshiRedrawTree(cell.contentView);
}

/* this account as a person, for the chips that show who reacted; the chips keep their number until it arrives */
- (void)loadSelfPerson {
    /* asked once per screen: a failed answer leaves the numbers, and no rebuild asks again */
    if (_selfPerson || _selfPersonAsked) return;
    _selfPersonAsked = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!items.count) {
            NSLog(@"noshigram: this account's picture for the reactions did not load: %@", errorName);
            return;
        }
        chat->_selfPerson = [[items objectAtIndex:0] retain];
        [chat rebuildItems];
    }];
}

/* who stands on the chips of a message instead of the numbers: in a private chat the two sides, elsewhere the
   people the server listed while there are few */
- (void)assignFacesOfMessage:(NoshiMessage *)message {
    NSArray *reactions = message.reactions;
    if (!reactions.count || reactions.count > NOSHI_REACTIONS_MAX) return;
    BOOL privateChat = (_dialog.kind == NOSHI_DIALOG_USER || _dialog.kind == NOSHI_DIALOG_BOT) && !_dialog.saved;
    noshi_reactions all;
    memset(&all, 0, sizeof(all));
    for (NoshiReaction *reaction in reactions) all.items[all.count++] = reaction.row;
    NoshiPerson *other = privateChat ? [self chatAsPerson] : nil;
    if (!_accountId) _accountId = [[NSNumber numberWithLongLong:[NoshiSession accountIdInDirectory:_session.directory]] retain];
    NSNumber *mine = _accountId;
    for (NSUInteger i = 0; i < reactions.count; ++i) {
        NoshiReaction *reaction = [reactions objectAtIndex:i];
        NSMutableArray *faces = [NSMutableArray array];
        BOOL complete = YES;
        switch (noshi_reaction_faces(&all, i, privateChat)) {
        case NOSHI_FACES_SELF_AND_OTHER:
            if (_selfPerson) [faces addObject:_selfPerson]; else complete = NO;
            [faces addObject:other];
            break;
        case NOSHI_FACES_SELF:
            if (_selfPerson) [faces addObject:_selfPerson]; else complete = NO;
            break;
        case NOSHI_FACES_OTHER:
            [faces addObject:other];
            break;
        case NOSHI_FACES_REACTORS:
            for (NSNumber *user in reaction.reactorIds) {
                NoshiPerson *person = [user isEqualToNumber:mine] ? _selfPerson : ([_reactorPeople objectForKey:user] ? [_reactorPeople objectForKey:user] : [_people objectForKey:user]);
                if (person) [faces addObject:person];
                else complete = NO;
                if (![user isEqualToNumber:mine] && (!person || !person.accessHash)) [self resolveReactor:user.longLongValue ofMessage:message];
            }
            break;
        default:
            complete = NO;
            break;
        }
        /* our own picture is the one thing asked for later */
        if (!complete && !_selfPerson && (privateChat || [reaction.reactorIds containsObject:mine])) [self loadSelfPerson];
        reaction.faces = complete && faces.count ? faces : nil;
    }
}

/* min users lack the access hash needed to load their photos */
- (void)resolveReactor:(long long)userId ofMessage:(NoshiMessage *)message {
    if (userId <= 0 || message.messageId <= 0) return;
    if (!_reactorLookups) _reactorLookups = [[NSMutableSet alloc] init];
    NSNumber *key = [NSNumber numberWithLongLong:userId];
    if ([_reactorLookups containsObject:key]) return;
    [_reactorLookups addObject:key];
    NoshiWeakReference *weak = _weak;
    [_session loadUser:userId ofMessage:message.messageId inDialog:_dialog completion:^(NoshiPerson *person, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!person) {
            NSLog(@"noshigram: the user %lld who reacted did not load: %@", userId, errorName);
            return;
        }
        if (!chat->_reactorPeople) chat->_reactorPeople = [[NSMutableDictionary alloc] init];
        [chat->_reactorPeople setObject:person forKey:key];
        [chat rebuildItems];
    }];
}

/* a photo or a video, which an album is made of */
- (BOOL)isAlbumPicture:(NoshiMessage *)message {
    noshi_preview_kind kind = message.media.kind;
    return !message.service && (kind == NOSHI_PREVIEW_PHOTO || kind == NOSHI_PREVIEW_VIDEO);
}

/* a file that may stand in a collage as the one under it */
- (BOOL)isAlbumMember:(NoshiMessage *)message {
    return [self isAlbumPicture:message] || (!message.service && message.media.kind == NOSHI_PREVIEW_FILE && !message.media.viewOnce);
}

- (BOOL)replyIsInThisChat:(NoshiMessage *)message {
    return !message.replyPeerKind || (message.replyPeerKind == _dialog.peerKind && message.replyPeerId == _dialog.peerId);
}

- (NSString *)replyCacheKey:(int32_t)identifier source:(NoshiDialog *)source {
    return [NSString stringWithFormat:@"%d/%lld/%d", source.peerKind, source.peerId, identifier];
}

- (NoshiDialog *)replySourceOfMessage:(NoshiMessage *)message {
    if ([self replyIsInThisChat:message]) return _dialog;
    long long key = message.replyPeerKind == 1 ? message.replyPeerId : -message.replyPeerId;
    NoshiPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:key]];
    if ((message.replyPeerKind == 1 || message.replyPeerKind == 3) && !person.accessHash) return nil;
    noshi_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = message.replyPeerKind;
    row.peer_id = message.replyPeerId;
    row.peer_hash = person.accessHash;
    row.kind = row.peer_kind == 1 ? (person.bot ? NOSHI_DIALOG_BOT : NOSHI_DIALOG_USER) : NOSHI_DIALOG_GROUP;
    NoshiMessage *original = [_replyCache objectForKey:[NSString stringWithFormat:@"%d/%lld/%d", row.peer_kind, row.peer_id, message.replyTo]];
    if ([original isKindOfClass:[NoshiMessage class]]) {
        if (original.post) row.kind = NOSHI_DIALOG_CHANNEL;
        if (original.topicId > 1) { row.forum = 1; row.topic_id = original.topicId; }
    }
    NSString *title = person.name.length ? person.name : NSLocalizedString(@"chat.reply.title", nil);
    NSData *utf8 = [title dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger size = MIN(utf8.length, sizeof(row.title) - 1);
    while (size && size < utf8.length && (((const uint8_t *)utf8.bytes)[size] & 0xc0u) == 0x80u) --size;
    memcpy(row.title, utf8.bytes, size);
    return [[[NoshiDialog alloc] initWithRow:&row] autorelease];
}

/* a message of a group whose sender the list does not know has no name over it, and a message sent through a bot has no "via @bot" line while the bot is unknown;
   the server is asked for the messages once, which brings their people */
- (void)fetchMissingSendersOf:(NSArray *)messages {
    NSMutableArray *ids = [NSMutableArray array];
    for (NoshiMessage *message in messages) {
        if (message.service || message.messageId <= 0) continue;
        BOOL senderMissing = !message.outgoing && !message.post && message.senderKey != 0 && ![_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
        BOOL botMissing = message.viaBotId != 0 && ![_people objectForKey:[NSNumber numberWithLongLong:message.viaBotId]];
        if (!senderMissing && !botMissing) continue;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if ([_senderLookups containsObject:key]) continue;
        [ids addObject:key];
        if (ids.count == NOSHI_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    if (!_senderLookups) _senderLookups = [[NSMutableSet alloc] init];
    [_senderLookups addObjectsFromArray:ids];
    NoshiWeakReference *weak = _weak;
    [_session loadMessagesWithIds:ids ofDialog:_dialog withPeople:^(NSArray *fetched, NSDictionary *people, NSString *errorName) {
        (void)fetched;
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) NSLog(@"noshigram: the senders of %lu messages did not load: %@", (unsigned long)ids.count, errorName);
        if (!people.count) return;
        [chat->_people addEntriesFromDictionary:people];
        [chat rebuildItems];
    }];
}

- (void)rebuildItems {
    if (!_rebuildNow && (_interacting || _keyboardMoving || _table.dragging || _table.decelerating)) { _livePending = YES; return; }
    if ([self replySwipeActive]) { [self scheduleLiveMessages]; return; }
    _livePending = NO;
    CFTimeInterval rebuildBegan = CACurrentMediaTime();
    /* an item keeps the colors of the palette it was laid out in, and the palette may change under a screen that stays (a night that comes by the clock, a switch made on the other
       pane of an ipad): items of an earlier one are dropped, so no row stays in the old colors */
    if (_themeRevision != NoshiThemeRevision()) {
        _themeRevision = NoshiThemeRevision();
        [_itemCache removeAllObjects];
        [self redrawVisibleCells];
    }
    /* the history is what tells that a user is a bot, when the chat was opened from a link that did not */
    [self loadCustomEmoji];
    /* the replies come from many people, so each message names its author and shows the picture as in a group */
    BOOL group = _dialog.kind == NOSHI_DIALOG_GROUP || _dialog.replies;
    NSArray *messages = [self orderedMessages];
    [self fetchMissingSendersOf:messages];
    NSTimeInterval serverNow = [[NSDate date] timeIntervalSince1970] + _sharingOffsetMilliseconds / 1000.0;
    NSTimeInterval nextExpiry = 0;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:messages.count + 8];
    NSMutableDictionary *kept = [NSMutableDictionary dictionaryWithCapacity:messages.count];
    NoshiMessage *previous = nil;
    NoshiChatItem *previousItem = nil;
    NSCalendar *calendar = NoshiDisplayCalendar();
    NoshiDaySpan daySpan = {0, 0, 0}, nextSpan = {0, 0, 0};
    NSInteger previousDay = 0;
    BOOL unreadShown = _unreadAnchor < 0 || _pinnedList || _startMessageId > 0;
    /* the colors of a quote do not depend on the message, so a walk over thousands of messages does not make them again for each */
    BOOL classicTheme = YES, darkTheme = NoshiThemeIsDark();
    UIColor *classicOwnQuote = classicTheme ? (darkTheme ? NoshiMixedColor(NoshiColorAccent(), [UIColor whiteColor], 0.55) : NoshiColorAccentDark()) : nil;
    UIColor *classicOtherQuote = classicTheme ? [UIColor colorWithWhite:darkTheme ? 0.74 : 0.40 alpha:1] : nil;
    for (NSUInteger at = 0; at < messages.count; ++at) {
        NoshiMessage *message = [messages objectAtIndex:at];
        BOOL sharingExpired = message.service == NOSHI_SERVICE_SHARING_REQUEST + 1 &&
            noshi_sharing_expired((message.serviceValue & 4) != 0, message.date, _sharingPeriod, (int64_t)serverNow);
        if (message.service == NOSHI_SERVICE_SHARING_REQUEST + 1 && !sharingExpired && message.date > 0) {
            NSTimeInterval deadline = (NSTimeInterval)message.date + _sharingPeriod + 1;
            if (deadline > serverNow && (!nextExpiry || deadline < nextExpiry)) nextExpiry = deadline;
        }
        if (message.messageId > 0 && [_openedOnce containsObject:[NSNumber numberWithInt:message.messageId]]) message.viewOnceOpened = YES;
        /* photos and videos sent together are one item: the run of messages that share an album number, from one sender on one day */
        NSMutableArray *album = nil;
        if (message.groupedId && [self isAlbumMember:message]) {
            NSMutableArray *run = [NSMutableArray arrayWithObject:message];
            NSUInteger last = at, pictures = [self isAlbumPicture:message] ? 1 : 0, files = 1 - pictures;
            while (last + 1 < messages.count) {
                NoshiMessage *next = [messages objectAtIndex:last + 1];
                BOOL picture = [self isAlbumPicture:next];
                if (next.groupedId != message.groupedId || next.senderKey != message.senderKey || next.outgoing != message.outgoing || ![self isAlbumMember:next] ||
                    NoshiDayKey(calendar, next.date, &nextSpan) != NoshiDayKey(calendar, message.date, &daySpan) || (picture ? pictures >= 10 : files >= 1)) break;
                [run addObject:next];
                if (picture) ++pictures; else ++files;
                ++last;
            }
            /* pictures alone make a collage; pictures with one file make a collage over the file, which owns the bubble. files alone stay messages of their own */
            if (pictures >= 1 && (pictures >= 2 || files == 1)) {
                album = run;
                at = last;
                if (files) for (NoshiMessage *part in run) if (![self isAlbumPicture:part]) { message = part; break; }
            }
        }
        NSInteger day = NoshiDayKey(calendar, message.date, &daySpan);
        if (!previous || day != previousDay) {
            [items addObject:[NoshiChatItem pillWithText:NoshiDayText(message.date)]];
            previous = nil;
            previousItem.joinsNext = NO;
            previousItem = nil;
        }
        /* with older history still unloaded the first row is not known to be the first unread one */
        if (!unreadShown && !message.outgoing && message.messageId > _unreadAnchor) {
            unreadShown = YES;
            if (at > 0 || !_canLoadMore) {
                [items addObject:[NoshiChatItem pillWithText:NSLocalizedString(@"chat.unread.line", nil)]];
                previous = nil;
                previousItem.joinsNext = NO;
                previousItem = nil;
            }
        }
        [self assignFacesOfMessage:message];
        NSNumber *key = [self cacheKeyForMessage:message];
        NoshiChatItem *item = [_itemCache objectForKey:key];
        NSString *role = [_senderRoles objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
        int32_t replyId = message.replyTo ? message.replyTo : message.sendReplyTo;
        /* every comment under a post answers that post, which the head of the thread shows already; a quote of it on each comment says nothing, as the root of a topic is not
           quoted either. an answer to another comment keeps its quote */
        if (_dialog.discussion && replyId > 0 && (replyId == message.threadId || [self isDiscussionRootId:replyId])) replyId = 0;
        BOOL localReply = replyId > 0 && [self replyIsInThisChat:message];
        NoshiDialog *replySource = replyId > 0 ? [self replySourceOfMessage:message] : nil;
        NoshiMessage *original = replyId > 0 && localReply ? [self messageWithId:replyId] : nil;
        /* the key is a formatted string, so it is made only for a reply whose original is not in the list */
        id cachedReply = replySource && !original ? [_replyCache objectForKey:[self replyCacheKey:replyId source:replySource]] : nil;
        if (!original && [cachedReply isKindOfClass:[NoshiMessage class]]) original = cachedReply;
        /* a message that was forwarded here is quoted under the name of whoever wrote it, as the other clients do, and not under the name of the person who forwarded it, which
           made an answer to it read as an answer to that person */
        NSString *originName = original ? NoshiForwardName(original, _people) : @"";
        NSString *replyTitle = replyId > 0 ? (original ? (originName.length ? originName : (original.post && !localReply ? replySource.title : [self senderNameOfMessage:original])) : NSLocalizedString(@"chat.reply.title", nil)) : nil;
        NSString *replyText = replyId > 0 ? (original ? NoshiMessageSummary(original) : NSLocalizedString(cachedReply || !replySource ? @"chat.reply.unavailable" : @"chat.reply.loading", nil)) : nil;
        if (replyId > 0 && message.replyQuote.length) replyText = message.replyQuote;
        /* an answer to a story names the story, since there is no message to show */
        if (replyId <= 0 && message.replyStory > 0) {
            replyTitle = NSLocalizedString(@"chat.reply.story", nil);
            replyText = NSLocalizedString(message.outgoing ? @"chat.reply.story.out" : @"chat.reply.story.in", nil);
        }
        /* every rebuild walks all loaded replies, and the original of a reply can be a whole post: copy it only when it has a line break */
        if (replyText.length && [replyText rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound)
            replyText = [[replyText stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        NSArray *replyEntities = original && !message.replyQuote.length ? original.entities : nil;
        if (replyEntities.count && !NoshiChatFlagGet(NoshiChatFlagShowReplyCustomEmoji)) {
            NSMutableArray *visible = [NSMutableArray array];
            for (NoshiTextEntity *entity in replyEntities) if (entity.style != NoshiTextStyleCustomEmoji) [visible addObject:entity];
            replyEntities = visible;
        }
        /* the classic bubble of somebody else is a neutral plate, and the accent on it reads as a link; our own bubble stands on the accent already, so the quote in it
           takes a light tint of the accent on the dark theme and the deep accent on the light one, where grey looked like a hole in the bubble. these two are the
           fallback for a quote with no known author, since the author's color replaces them below in both styles */
        UIColor *replyColor = nil;
        if (replyId > 0 || message.replyStory > 0) {
            if (classicTheme) replyColor = message.outgoing ? classicOwnQuote : classicOtherQuote;
            else replyColor = NoshiColorBubbleLink(message.outgoing);
            if (original && NoshiChatFlagGet(NoshiChatFlagReplyColors)) {
                /* a forward whose author hides the account has a name and no key, and takes no color rather than the color of the person who forwarded it */
                long long authorKey = originName.length ? original.forwardKey : original.senderKey;
                NoshiPerson *author = authorKey ? [_people objectForKey:[NSNumber numberWithLongLong:authorKey]] : nil;
                if (author) {
                    UIColor *named = NoshiNameColor(author.nameColor, llabs(authorKey), darkTheme);
                    /* on the accent of our own bubble the plain name color sinks in, so it is taken half way to white, which keeps the hue of the person who is quoted */
                    replyColor = message.outgoing ? NoshiMixedColor(named, [UIColor whiteColor], 0.55) : named;
                }
            }
        }
        if (item && (!(item.replyTitle == replyTitle || [item.replyTitle isEqualToString:replyTitle]) ||
                     !(item.replyText == replyText || [item.replyText isEqualToString:replyText]) ||
                     (replyId > 0 && ![item.replyColor isEqual:replyColor]) ||
                     !(item.replyEntities == replyEntities || [item.replyEntities isEqualToArray:replyEntities]))) item = nil;
        if (item && (![item reflectsMessage:message] || ![item reflectsPeople:_people role:role] || ![item reflectsAlbum:album ? album : [NSArray arrayWithObject:message]])) item = nil;
        if (item && message.service == NOSHI_SERVICE_SHARING_REQUEST + 1 && item.sharingExpired != sharingExpired) item = nil;
        if (!item) {
            item = album ? [NoshiChatItem itemForAlbum:album group:group people:_people role:role] : [NoshiChatItem itemForMessage:message group:group people:_people role:role];
            if (message.service == NOSHI_SERVICE_SHARING_REQUEST + 1) item.sharingExpired = sharingExpired;
            [item wordCommunityLineForDialog:_dialog people:_people];
            if (_dialog.replies) {
                [item dropForwardText];
                if (message.forwardOriginId && message.forwardOriginMessage > 0) [item showOpenChatRow];
            }
            /* the post at the head of the comments is the copy the group made of the post of its channel, and the line that names the channel says what the thread is about
               already */
            if ([self isDiscussionRootId:message.messageId]) [item dropForwardText];
            [item setReplyTitle:replyTitle text:replyText color:replyColor];
            item.replyEntities = replyEntities;
            /* the list of a search shows its words on a plate in every message it found */
            if (_pinnedList && _searchQuery.length) item.highlightQuery = _searchQuery;
            item.reactionsHidden = [self reactionsHidden];
            item.transcript = [_transcripts objectForKey:[NSNumber numberWithInt:message.messageId]];
        }
        [kept setObject:item forKey:key];
        BOOL joins = previous && [self message:previous joins:message];
        previousDay = day;
        /* the gap above a bubble is part of its layout, the tucked in corner below the one before it is only drawing */
        if (item.joinsPrevious != joins) {
            item.joinsPrevious = joins;
            [item invalidateLayout];
        }
        previousItem.joinsNext = joins;
        item.joinsNext = NO;
        item.read = message.outgoing && message.messageId > 0 && message.messageId <= [self readOutboxMaxId];
        [items addObject:item];
        previous = message;
        previousItem = item;
    }
    [_itemCache release];
    _itemCache = [kept retain];
    [self applyItems:items];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sharingExpiryReached) object:nil];
    if (_visible && nextExpiry > serverNow)
        [self performSelector:@selector(sharingExpiryReached) withObject:nil afterDelay:nextExpiry - serverNow];
    [self scheduleReplyPreviews];
    if (!_pinnedList) [_bots messagesChanged:messages loaded:_loadedFirst];
    _rebuildEndedAt = CACurrentMediaTime();
    _rebuildCost = _rebuildEndedAt - rebuildBegan;
}

- (BOOL)sharingExpired:(NoshiMessage *)message {
    int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] + _sharingOffsetMilliseconds / 1000.0);
    return noshi_sharing_expired((message.serviceValue & 4) != 0, message.date, _sharingPeriod, now) != 0;
}

- (void)sharingExpiryReached {
    [self scheduleLiveMessages];
}

/* only missing originals on screen are fetched, in one bounded batch; reply history never adds rows to the chat */
- (void)scheduleReplyPreviews {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadReplyPreviews) object:nil];
    [self performSelector:@selector(loadReplyPreviews) withObject:nil afterDelay:0];
}

- (void)loadReplyPreviews {
    if (_loadingReplies || _interacting || !_visible) return;
    NSMutableArray *ids = [NSMutableArray array];
    NoshiDialog *source = nil;
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        NoshiMessage *message = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        int32_t reply = message.replyTo ? message.replyTo : message.sendReplyTo;
        if (reply <= 0 || ([self replyIsInThisChat:message] && [self messageWithId:reply])) continue;
        NoshiDialog *candidate = [self replySourceOfMessage:message];
        if (!candidate || [_replyCache objectForKey:[self replyCacheKey:reply source:candidate]]) continue;
        if (source && (source.peerKind != candidate.peerKind || source.peerId != candidate.peerId)) continue;
        source = candidate;
        NSNumber *key = [NSNumber numberWithInt:reply];
        if (![ids containsObject:key]) [ids addObject:key];
        if (ids.count == NOSHI_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    _loadingReplies = YES;
    NSUInteger generation = _replyGeneration;
    NoshiWeakReference *weak = _weak;
    [_session loadMessagesWithIds:ids ofDialog:source withPeople:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || generation != chat->_replyGeneration) return;
        chat->_loadingReplies = NO;
        if (errorName) NSLog(@"noshigram: reply originals did not load: %@", errorName);
        for (NSNumber *key in ids) [chat->_replyCache setObject:[NSNull null] forKey:[chat replyCacheKey:key.intValue source:source]];
        for (NoshiMessage *original in messages) [chat->_replyCache setObject:original forKey:[chat replyCacheKey:original.messageId source:source]];
        if (people) [chat->_people addEntriesFromDictionary:people];
        [chat rebuildItems];
    }];
}

- (void)messageCellDidTapReply:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    int32_t reply = message.replyTo ? message.replyTo : message.sendReplyTo;
    if (reply <= 0) return;
    if ([self replyIsInThisChat:message]) { [self jumpToMessageId:reply]; return; }
    NoshiDialog *source = [self replySourceOfMessage:message];
    if (!source) { NoshiShowNotice(nil, NSLocalizedString(@"chat.reply.unavailable", nil)); return; }
    NoshiChatController *page = [[[NoshiChatController alloc] initWithSession:_session dialog:source avatars:_avatars media:_media stickers:_stickers] autorelease];
    page.startMessageId = reply;
    [self.navigationController pushViewController:page animated:YES];
}

/* swaps the rows in; a change that only adds or only removes rows keeps the others and reloads those whose content
   differs */

- (void)applyItems:(NSArray *)items {
    BOOL moving = _interacting || _table.dragging || _table.decelerating;
    /* the flag follows only a finger, so a list that was left at its end by a keyboard, a reply or a jump kept the flag off and stood still under the new message; the offset
       says where the list is, and a list within the distance of the finger rule is at its end */
    BOOL atEnd = !_window && [self scrollLimitMax] - _table.contentOffset.y <= BOTTOM_FOLLOW_DISTANCE;
    BOOL follows = (_stickToBottom || atEnd) && !moving;
    _updatingItems = YES;
    NSArray *oldItems = [_items retain];
    NSUInteger oldCount = oldItems.count;
    NSUInteger newCount = items.count;
    BOOL replacedLocal = _localReplaced;
    _localReplaced = NO;

    NoshiChatItem *anchor = nil;
    NSArray *visible = [_table indexPathsForVisibleRows];
    /* the rows on screen from the top down, each with its distance from the offset: when the page changes the day pills (a pill of the same day moves up to the
       top of the new page, or the unread pill goes), the first row may be gone from the new list, and the next one that is still there holds the place.
       With no row kept the offset stays while rows are added above it, which is a jump back by a page */
    NSMutableArray *anchors = [NSMutableArray array];
    NSMutableArray *anchorOffsets = [NSMutableArray array];
    if (!follows) {
        for (NSIndexPath *path in visible) {
            if ((NSUInteger)path.row >= oldCount) continue;
            [anchors addObject:[oldItems objectAtIndex:(NSUInteger)path.row]];
            [anchorOffsets addObject:[NSNumber numberWithDouble:_table.contentOffset.y - [_table rectForRowAtIndexPath:path].origin.y]];
        }
        if (anchors.count) anchor = [[anchors objectAtIndex:0] retain];
    }

    NSUInteger prefix = 0;
    while (prefix < MIN(oldCount, newCount) &&
           [[oldItems objectAtIndex:prefix] isSameRowAs:[items objectAtIndex:prefix]]) ++prefix;

    NSUInteger suffix = 0;
    while (suffix < oldCount - prefix && suffix < newCount - prefix &&
           [[oldItems objectAtIndex:oldCount - suffix - 1] isSameRowAs:[items objectAtIndex:newCount - suffix - 1]]) ++suffix;

    NSUInteger removed = oldCount - prefix - suffix;
    NSUInteger inserted = newCount - prefix - suffix;
    BOOL simple = removed == 0 || inserted == 0;
    NSMutableArray *refresh = [NSMutableArray array], *inPlace = [NSMutableArray array];
    BOOL reactionsChanged = NO;
    if (simple) {
        for (NSUInteger i = 0; i < prefix + suffix; ++i) {
            NSUInteger oldIndex = i < prefix ? i : oldCount - suffix + (i - prefix);
            NSUInteger newIndex = i < prefix ? i : newCount - suffix + (i - prefix);
            NoshiChatItem *before = [oldItems objectAtIndex:oldIndex];
            NoshiChatItem *after = [items objectAtIndex:newIndex];
            if (![after displaysSameAs:before]) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)newIndex inSection:0];
                BOOL onlyReactions = !removed && !inserted && [after hasDifferentReactionsFrom:before];
                if (onlyReactions) reactionsChanged = YES;
                /* a reloaded row may come back as another cell, which has not seen the chips that were there and so can neither grow the new one nor shrink the old one;
                   the cell that is on screen is configured again where it stands, and the table measures the rows again under it */
                if (onlyReactions && [_table cellForRowAtIndexPath:path]) [inPlace addObject:path];
                else [refresh addObject:path];
            }
        }
    }

    /* the rows that stay slide to their new places while the removed one turns to dust, as the item animator of exteraless moves them, and
       the sizes they start from are those of the screen before the rows change */
    BOOL slide = NO, slideDust = NO;
    NSMutableDictionary *slideFrom = nil;
    /* ios 6 sorts the index paths of a batch of row updates and measures every row for each step, so hundreds of rows at once (a long list of pinned messages
       that gets its reply previews) held the main thread until the watchdog ended the app; one reload goes through the rows once */
    BOOL bulk = simple && removed + inserted + refresh.count > BULK_ROWS_MAX;
    [_items release];
    _items = [items retain];
    if (_greeting) [self.view setNeedsLayout];

    if (!simple || bulk) {
        [_table reloadData];
    } else {
        if (removed || inserted) {
            NSMutableArray *paths = [NSMutableArray array];
            for (NSUInteger i = 0; i < (removed ? removed : inserted); ++i)
                [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)(prefix + i) inSection:0]];
            /* the row of a message that was on its way goes silently, since its copy from the server stands in the list already; fading or dusting it reads as a deletion */
            BOOL animate = oldCount > 0 && !(removed && replacedLocal) && [self rowChangesMayAnimate];
            if (removed) {
                /* fading rows below an anchor would slide while the offset jumps */
                BOOL dust = animate && removed <= DUST_ROWS_MAX && NoshiLiteEnabled(NOSHI_LITE_CHAT_THANOS);
                /* without the dust the item animator fades the removed row out in 120 ms and slides the others in 250 ms; the table's own fade would
                   not move them together */
                BOOL snap = dust || (animate && !anchor && removed <= DUST_ROWS_MAX);
                NSMutableArray *pictures = snap ? [NSMutableArray array] : nil, *frames = snap ? [NSMutableArray array] : nil;
                for (NSIndexPath *path in paths) {
                    NoshiChatItem *gone = [oldItems objectAtIndex:(NSUInteger)path.row];
                    UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
                    if (snap && cell && gone.kind != NoshiChatItemPill) {
                        UIImage *picture = NoshiDustSnapshot(cell);
                        if (picture) {
                            [pictures addObject:picture];
                            /* table-owned dust would scroll below the input while the list follows its end */
                            [frames addObject:[NSValue valueWithCGRect:[_table convertRect:cell.frame toView:self.view]]];
                        }
                    }
                }
                if (pictures.count) {
                    slide = YES;
                    slideFrom = [NSMutableDictionary dictionary];
                    for (NSIndexPath *seen in visible) {
                        UITableViewCell *cell = [_table cellForRowAtIndexPath:seen];
                        if (cell) [slideFrom setObject:[NSValue valueWithCGRect:[_table convertRect:cell.frame toView:self.view]] forKey:[NSNumber numberWithInteger:seen.row]];
                    }
                }
                [_table beginUpdates];
                [_table deleteRowsAtIndexPaths:paths withRowAnimation:pictures.count || !animate || anchor ? UITableViewRowAnimationNone : UITableViewRowAnimationFade];
                [_table endUpdates];
                for (NSUInteger i = 0; i < pictures.count; ++i) {
                    UIImage *picture = [pictures objectAtIndex:i];
                    CGRect frame = [[frames objectAtIndex:i] CGRectValue];
                    if (dust) NoshiDustDisperse(picture, frame, self.view);
                    else [self fadeAwayPicture:picture frame:frame];
                }
                slideDust = dust;
            } else {
                [_table beginUpdates];
                [_table insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
                [_table endUpdates];
                if (animate && !anchor && inserted <= ENTER_ROWS_MAX) [self animateEnterOfRows:paths items:items];
            }
        }
        if (refresh.count) {
            [_table reloadRowsAtIndexPaths:refresh withRowAnimation:UITableViewRowAnimationNone];
        }
        if (inPlace.count) {
            for (NSIndexPath *path in inPlace) {
                NoshiMessageCell *cell = (NoshiMessageCell *)[_table cellForRowAtIndexPath:path];
                CGFloat from = [cell bodyHeight];
                [self configureMessageCell:cell forRow:(NSUInteger)path.row];
                [cell growBodyFromHeight:from];
            }
            [_table beginUpdates];
            [_table endUpdates];
        }
    }
    for (NoshiChatItem *item in items) [item markDisplayed];
    /* a row swapped for another (the pending message for the copy of the server) reloads the table, and a list that was following its end stays on it */
    [_table layoutIfNeeded];

    for (NSUInteger kept = 0; kept < anchors.count; ++kept) {
        NoshiChatItem *candidate = [anchors objectAtIndex:kept];
        BOOL placed = NO;
        for (NSUInteger index = 0; index < newCount; ++index) {
            if (![candidate isSameRowAs:[items objectAtIndex:index]]) continue;
            CGFloat y = [_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]].origin.y + [[anchorOffsets objectAtIndex:kept] doubleValue];
            [_table setContentOffset:CGPointMake(0, y) animated:NO];
            placed = YES;
            break;
        }
        if (placed) break;
    }
    [anchor release];
    [oldItems release];
    _updatingItems = NO;
    if (!moving) _stickToBottom = follows;
    /* a list that follows its end goes there at once under the rows that slide, or the two movements would add up */
    /* a full reload has no anchor, and animating from its old offset would show a jump */
    if (follows && newCount) [self scrollToBottomAnimated:!reactionsChanged && !slide && simple && !bulk && oldCount > 0 && !(inserted && !prefix && suffix) && [self rowChangesMayAnimate]];
    if (slide) {
        [_table layoutIfNeeded];
        for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
            NSUInteger newRow = (NSUInteger)path.row, oldRow = newRow < prefix ? newRow : newRow + removed;
            NSValue *from = [slideFrom objectForKey:[NSNumber numberWithUnsignedInteger:oldRow]];
            UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
            if (!from || !cell) continue;
            CGFloat dy = [from CGRectValue].origin.y - [_table convertRect:cell.frame toView:self.view].origin.y;
            if (fabs(dy) < 0.5) continue;
            CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
            move.fromValue = [NSNumber numberWithDouble:dy];
            move.toValue = [NSNumber numberWithDouble:0];
            if (slideDust) {
                /* the move of the item animator with the effect on: 250 ms times 1.9, easing out */
                move.duration = 0.475;
                move.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0 :0 :0.58f :1];
            } else {
                /* ChatListItemAnimator.DEFAULT_DURATION and DEFAULT_INTERPOLATOR */
                move.duration = 0.25;
                move.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.19919473f :0.010644531f :0.27920937f :0.91025391f];
            }
            [cell.layer addAnimation:move forKey:@"noshigram.dust.slide"];
        }
    }
    [self refreshAnimations];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markReadIfNeeded) object:nil];
    [self performSelector:@selector(markReadIfNeeded) withObject:nil afterDelay:0];
}

/* the screen is up and drawing: a row that appears or goes while the app sleeps, or before the first page is on screen, is not worth an effect */
- (BOOL)rowChangesMayAnimate {
    return _visible && _loadedFirst && !_opening && [UIApplication sharedApplication].applicationState == UIApplicationStateActive && NoshiLiteSmoothTransitions();
}

/* rows added away from the end fade in from their tail; following the end belongs to the scroll driver */
/* the removed row of the item animator with the dust off: its alpha goes to zero over RecyclerView's default remove duration, 120 ms, on the
   default ease in and out of an ObjectAnimator */
- (void)fadeAwayPicture:(UIImage *)picture frame:(CGRect)frame {
    UIImageView *ghost = [[[UIImageView alloc] initWithImage:picture] autorelease];
    ghost.frame = frame;
    ghost.userInteractionEnabled = NO;
    [self.view addSubview:ghost];
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ ghost.alpha = 0; }
                     completion:^(BOOL finished) {
        (void)finished;
        [ghost removeFromSuperview];
    }];
}

- (void)animateEnterOfRows:(NSArray *)paths items:(NSArray *)items {
    BOOL zoom = NoshiLiteEnabled(NOSHI_LITE_CHAT_SCALE);
    if (_stickToBottom) return;
    for (NSIndexPath *path in paths) {
        UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
        if (!cell || (NSUInteger)path.row >= items.count) continue;
        NoshiChatItem *item = [items objectAtIndex:(NSUInteger)path.row];
        if (item.kind == NoshiChatItemPill) {
            NoshiAnimateEnter(cell, CGAffineTransformIdentity, 0, NOSHI_MOTION_ENTER);
            continue;
        }
        BOOL outgoing = item.message.outgoing;
        CGFloat scale = zoom ? (outgoing ? 0.8f : 0.92f) : 1;
        CGSize size = cell.bounds.size;
        CGPoint corner = CGPointMake(outgoing ? size.width - 14 : 14, size.height);
        CGAffineTransform from = CGAffineTransformMake(scale, 0, 0, scale, (1 - scale) * (corner.x - size.width / 2), (1 - scale) * (corner.y - size.height / 2));
        NoshiAnimateEnter(cell, from, 0, zoom && outgoing ? NOSHI_MOTION_SPRING : NOSHI_MOTION_ENTER);
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (!_items.count) return;
    [_table layoutIfNeeded];
    CGFloat end = _table.contentSize.height - _table.bounds.size.height + _table.contentInset.bottom;
    CGFloat y = MAX(-_table.contentInset.top, end);
    if (!animated || fabs(_table.contentOffset.y - y) <= 0.5) {
        [self stopFollowingBottom];
        [_table setContentOffset:CGPointMake(0, y) animated:NO];
        return;
    }
    if (_followLink) return;
    _followingBottom = YES;
    _followTime = 0;
    NoshiReactionPollTarget *target = [[[NoshiReactionPollTarget alloc] initWithReference:_weak] autorelease];
    _followLink = [[CADisplayLink displayLinkWithTarget:target selector:@selector(follow:)] retain];
    [_followLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (BOOL)replySwipeActive {
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiMessageCell class]] && [(NoshiMessageCell *)cell replySwipeActive]) return YES;
    }
    return NO;
}

- (void)stopFollowingBottom {
    [self stopJump];
    [_followLink invalidate];
    [_followLink release];
    _followLink = nil;
    _followingBottom = NO;
    _followTime = 0;
    _followBegan = 0;
}

- (void)advanceBottom:(CADisplayLink *)link {
    if (!_visible || _table.tracking || _table.dragging) { [self stopFollowingBottom]; return; }
    if (_interacting || _table.decelerating) { _followTime = link.timestamp; return; }
    if ([self replySwipeActive]) { _followTime = link.timestamp; return; }
    CGFloat target = [self scrollLimitMax];
    double next = 0;
    CFTimeInterval elapsed = _followTime ? link.timestamp - _followTime : 1.0 / 60.0;
    _followTime = link.timestamp;
    if (!_followBegan) _followBegan = link.timestamp;
    if (noshi_scroll_follow(_table.contentOffset.y, target, elapsed, &next) != NOSHI_OK) return;
    /* the pace builds up over the first 150 ms, since the follow used to start at its fastest and showed as a jerk */
    double ramp = MIN(1.0, (link.timestamp - _followBegan) / 0.15);
    next = _table.contentOffset.y + (next - _table.contentOffset.y) * ramp * ramp;
    [_table setContentOffset:CGPointMake(0, (CGFloat)next) animated:NO];
    if (fabs(target - next) <= 0.5) {
        [_table setContentOffset:CGPointMake(0, target) animated:NO];
        [self stopFollowingBottom];
        [self refreshAnimations];
    }
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)indexPath.row];
    [item layoutForWidth:tableView.bounds.size.width];
    return item.height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"message";
    NoshiMessageCell *cell = (NoshiMessageCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[NoshiMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        cell.delegate = self;
    }
    [self configureMessageCell:cell forRow:(NSUInteger)indexPath.row];
    return cell;
}

- (void)configureMessageCell:(NoshiMessageCell *)cell forRow:(NSUInteger)row {
    NoshiChatItem *item = [_items objectAtIndex:row];
    /* a cell that is reused while its row was coming in must not carry the entrance to the next row */
    NoshiCancelEnter(cell);
    [item layoutForWidth:_table.bounds.size.width];
    cell.activationDeferred = _interacting;
    cell.stickerLibrary = _stickers;
    [cell configureWithItem:item media:_media avatars:_avatars];
    [cell setSelecting:_selecting selected:[_selectedIds containsObject:[NSNumber numberWithInt:item.message.messageId]] animated:NO];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if ([cell isKindOfClass:[NoshiMessageCell class]]) {
        [(NoshiMessageCell *)cell setAnimating:_visible];
        [self scheduleReplyPreviews];
    }
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if ([cell isKindOfClass:[NoshiMessageCell class]]) [(NoshiMessageCell *)cell setAnimating:NO];
}

#pragma mark scrolling

- (CGFloat)scrollLimitMin {
    return -_table.contentInset.top;
}

- (CGFloat)scrollLimitMax {
    return MAX([self scrollLimitMin], _table.contentSize.height - _table.bounds.size.height + _table.contentInset.bottom);
}

/* where the view will be in a moment, or nothing when the numbers do not allow a guess */
- (BOOL)predictedOffset:(CGFloat *)predicted {
    double value = 0;
    double offset = _table.contentOffset.y;
    if (noshi_scroll_predict(&_scroll, offset, _table.bounds.size.height, _scrollTargetKnown, _scrollTargetOffset,
                               [self scrollLimitMin], [self scrollLimitMax], &value) != NOSHI_OK) return NO;
    *predicted = (CGFloat)value;
    return YES;
}

/* asks for the next page before the view gets to the top of the loaded rows, as early as the speed calls for */
- (void)loadOlderIfNeeded {
    /* a jump to a message that is held goes through the top of the loaded rows, and a page that arrived there would have moved the rows under it */
    if (_jumpLink) return;
    CGFloat predicted = 0;
    if (![self predictedOffset:&predicted]) return;
    CGFloat top = MIN(_table.contentOffset.y, predicted) + _table.contentInset.top;
    if (noshi_scroll_wants_older(top, _scroll.velocity, _table.bounds.size.height)) [self loadOlder];
}

/* the pictures of the rows the view is about to reach are fetched and decoded before it needs them */
- (void)prepareAhead:(BOOL)force {
    CGFloat height = _table.bounds.size.height;
    CGFloat offset = _table.contentOffset.y;
    if (height < 1 || !_items.count) return;
    if (!force && fabs(offset - _preparedOffset) < height * 0.5) return;
    CGFloat predicted = 0;
    noshi_scroll_window window;
    if (![self predictedOffset:&predicted] || noshi_scroll_prepare_window(offset, predicted, _scroll.velocity, height, &window) != NOSHI_OK) return;
    _preparedOffset = offset;
    CGRect span = CGRectMake(0, window.min_y, _table.bounds.size.width, window.max_y - window.min_y);
    CGRect shown = _table.bounds;
    NSMutableArray *ahead = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForRowsInRect:span]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        CGRect row = [_table rectForRowAtIndexPath:path];
        if (CGRectIntersectsRect(row, shown)) continue;
        CGFloat gap = row.origin.y > CGRectGetMaxY(shown) ? row.origin.y - CGRectGetMaxY(shown) : CGRectGetMinY(shown) - CGRectGetMaxY(row);
        [ahead addObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:gap], [NSNumber numberWithInteger:path.row], nil]];
    }
    [ahead sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        return [[a objectAtIndex:0] compare:[b objectAtIndex:0]];
    }];
    NSUInteger count = MIN(ahead.count, (NSUInteger)PREPARE_ROWS_MAX);
    for (NSUInteger i = 0; i < count; ++i) {
        NSUInteger row = [[[ahead objectAtIndex:i] objectAtIndex:1] unsignedIntegerValue];
        NoshiChatItem *aheadItem = [_items objectAtIndex:row];
        [NoshiMessageCell prepareItem:aheadItem media:_media];
        /* in a group every run of messages has a picture of its author: without this it decodes after the row is shown and fades in over the initials */
        if (aheadItem.showsAvatar && aheadItem.senderPerson.photo) [_avatars loadImageForPhoto:aheadItem.senderPerson.photo completion:nil];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_updatingItems || _layingOutChat || _keyboardMoving) return;
    CGFloat distance = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.size.height + scrollView.contentInset.bottom;
    BOOL moving = scrollView.tracking || scrollView.dragging || scrollView.decelerating;
    if (!_followingBottom)
        _stickToBottom = noshi_scroll_tracks_bottom(_stickToBottom, _interacting && moving,
                                                     _scroll.last_offset, scrollView.contentOffset.y, [self scrollLimitMax]);
    [self showNextChatHintForOverscroll:-distance scrollView:scrollView];
    if (_window) _stickToBottom = NO;
    [self showToEnd:_window || distance > scrollView.bounds.size.height * 1.2f];
    /* a move the code made, such as a row inserted above or a keyboard, says nothing about how fast a finger goes */
    if (moving)
        noshi_scroll_sample(&_scroll, scrollView.contentOffset.y, CFAbsoluteTimeGetCurrent(), scrollView.bounds.size.height);
    else
        noshi_scroll_begin(&_scroll, scrollView.contentOffset.y, CFAbsoluteTimeGetCurrent());
    [self loadOlderIfNeeded];
    [self loadNewerIfNeeded:distance];
    [self refreshPinnedForVisible];
    [self prepareAhead:NO];
    [self refreshAnimationsIfRowsChanged];
    [self scheduleScrollReadCheck];
}

/* a scroll reports every frame, and each report used to cancel and start two run loop timers; one check at most every quarter second sees the rows the finger
   has reached, and the last report of a scroll always leaves one pending or just run, so the rows where it stopped are never missed */
- (void)scheduleScrollReadCheck {
    if (_scrollReadPending) return;
    _scrollReadPending = YES;
    [self performSelector:@selector(runScrollReadCheck) withObject:nil afterDelay:0.25];
}

- (void)runScrollReadCheck {
    _scrollReadPending = NO;
    [self scheduleVisibleMentionsRead];
    [self markReadIfNeeded];
}

/* pulling past the end of a channel, or of a topic of a forum, offers the next one with unread messages; letting go far enough opens it */
- (void)showNextChatHintForOverscroll:(CGFloat)over scrollView:(UIScrollView *)scrollView {
    BOOL eligible = _dialog.kind == NOSHI_DIALOG_CHANNEL || [self isForumTopic];
    if (!eligible || !_nextChatProvider || _pinnedList || _updatingItems || !scrollView.dragging || over <= 0 || !_stickToBottom) {
        if (_nextHint.progress > 0) _nextHint.progress = 0;
        return;
    }
    if (!_nextDialog) {
        _nextDialog = [_nextChatProvider(_dialog) retain];
        if (_nextDialog) [self fillNextHint];
    }
    if (!_nextDialog) return;
    _nextHint.frame = CGRectMake(0, scrollView.contentSize.height, scrollView.bounds.size.width, [NoshiNextChatHint pullDistance]);
    _nextHint.progress = over / [NoshiNextChatHint pullDistance];
}

/* a topic carries its own icon; the picture of a channel comes from the avatar cache, and the hint shows its first letter until it lands */
- (void)fillNextHint {
    NoshiDialog *next = _nextDialog;
    UIImage *icon = nil;
    if (next.topicId > 0) icon = NoshiTopicIconImage(next);
    else if (next.photo) icon = [_avatars cachedImageForPhoto:next.photo];
    [_nextHint setTitle:next.title unread:next.unreadCount icon:icon];
    if (icon || next.topicId > 0 || !next.photo) return;
    NoshiWeakReference *weak = _weak;
    [_avatars loadImageForPhoto:next.photo completion:^(UIImage *image) {
        NoshiChatController *chat = weak.target;
        if (chat && image && chat->_nextDialog == next) [chat->_nextHint setIcon:image];
    }];
}

- (void)openNextChat {
    NoshiDialog *next = [[_nextDialog retain] autorelease];
    UINavigationController *navigation = self.navigationController;
    if (!next || !navigation || navigation.topViewController != self) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:next avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.nextChatProvider = _nextChatProvider;
    chat.closeHandler = _closeHandler;
    /* the new chat takes this one's place, so back goes to the list as it did before */
    NSMutableArray *stack = [NSMutableArray arrayWithArray:navigation.viewControllers];
    [stack removeObject:self];
    [stack addObject:chat];
    [_nextDialog release];
    _nextDialog = nil;
    [navigation setViewControllers:stack animated:YES];
}

- (void)showToEnd:(BOOL)show {
    if (show == _toEndShown) return;
    _toEndShown = show;
    if (show) _toEnd.hidden = NO;
    [UIView animateWithDuration:0.18 animations:^{
        _toEnd.alpha = show ? 1 : 0;
        [self placeReactionJump];
    } completion:^(BOOL finished) {
        if (finished && !_toEndShown) _toEnd.hidden = YES;
    }];
}

/* the heart takes the place of the way down when that is hidden, and stands over it when it shows */
- (void)placeReactionJump {
    CGRect base = _toEnd.frame;
    CGFloat y = _toEndShown ? base.origin.y - 52 : base.origin.y;
    _reactionJump.frame = CGRectMake(base.origin.x, y, 44, 44);
    CGFloat width = MAX(22, ceil([_reactionBadge sizeThatFits:CGSizeMake(80, 22)].width) + 12);
    _reactionBadge.frame = CGRectMake(CGRectGetMaxX(_reactionJump.frame) - width + 6, y - 6, width, 22);
}

- (void)refreshReactionJump {
    BOOL show = _unreadReactionIds.count > 0;
    _reactionJump.hidden = !show;
    _reactionBadge.hidden = !show;
    _reactionBadge.text = _unreadReactionIds.count > 999 ? @"999+" : [NSString stringWithFormat:@"%lu", (unsigned long)_unreadReactionIds.count];
    [self placeReactionJump];
}

/* the server lists the messages that got a reaction we have not seen; a chat opened from the list knows how many there are before it asks */
- (void)loadUnreadReactions {
    if (_dialog.reactions <= 0 || self.pinnedList) return;
    NoshiWeakReference *weak = _weak;
    [_session loadUnreadReactionsOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!messages) {
            NSLog(@"noshigram: the unread reactions of chat %lld did not load: %@", chat->_dialog.peerId, errorName);
            return;
        }
        NSMutableArray *ids = [[NSMutableArray alloc] init];
        for (NoshiMessage *message in messages) if (message.messageId > 0) [ids addObject:[NSNumber numberWithInt:message.messageId]];
        [chat->_unreadReactionIds release];
        chat->_unreadReactionIds = ids;
        chat->_ghostReactionIndex = 0;
        [chat refreshReactionJump];
    }];
}

/* the oldest unseen reaction first, which reads forward; the last one seen tells the server that all of them were */
- (void)reactionJumpTapped {
    if (!_unreadReactionIds.count) return;
    if (!noshi_read_action_allowed(0, NOSHI_READ_AUTOMATIC)) {
        NSUInteger index = _unreadReactionIds.count - 1 - (_ghostReactionIndex++ % _unreadReactionIds.count);
        [self jumpToMessageId:[[_unreadReactionIds objectAtIndex:index] intValue]];
        return;
    }
    int32_t messageId = [[_unreadReactionIds lastObject] intValue];
    [_unreadReactionIds removeLastObject];
    if (!_unreadReactionIds.count) [self sendReactionsRead:NO];
    [self refreshReactionJump];
    [self jumpToMessageId:messageId];
}

/* the server counts the reactions of the chat as seen and says nothing back, so the row of the list is cleared here */
- (void)sendReactionsRead:(BOOL)explicit {
    if (![_session markReactionsReadOfDialog:_dialog explicit:explicit]) return;
    [_dialog clearReactions];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
}

/* a message with an unseen reaction that comes onto the screen counts as read, as in the android client; the last one tells the server */
- (void)scheduleVisibleReactionsRead {
    if (!_unreadReactionIds.count) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markVisibleReactionsRead) object:nil];
    [self performSelector:@selector(markVisibleReactionsRead) withObject:nil afterDelay:0];
}

- (void)markVisibleReactionsRead {
    if (!_visible || _pinnedList || !_unreadReactionIds.count || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    BOOL seen = NO;
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)path.row];
        /* the day marker and the unread line are rows without a message, and arrayWithObject: throws on nil: on ios 6 that took the app down from this delayed call as soon as
           one of them was on the screen with an unseen reaction */
        NSMutableArray *messages = [NSMutableArray array];
        if (item.message) [messages addObject:item.message];
        [messages addObjectsFromArray:item.albumMessages];
        for (NoshiMessage *message in messages) {
            NSUInteger at = [_unreadReactionIds indexOfObject:[NSNumber numberWithInt:message.messageId]];
            if (at == NSNotFound) continue;
            [_unreadReactionIds removeObjectAtIndex:at];
            seen = YES;
        }
    }
    if (!seen) return;
    if (!_unreadReactionIds.count) [self sendReactionsRead:NO];
    [self refreshReactionJump];
}

- (void)reactionJumpHeld:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || !_unreadReactionIds.count) return;
    NoshiSymbol symbols[1] = {NoshiSymbolCheckDouble};
    NoshiWeakReference *weak = _weak;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"chat.reactions.readall", nil)] symbols:symbols handler:^(NSUInteger index) {
        (void)index;
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat->_unreadReactionIds removeAllObjects];
        [chat sendReactionsRead:YES];
        [chat refreshReactionJump];
    }] autorelease];
    CGRect button = _reactionJump.frame;
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(button), CGRectGetMaxY(button))];
}

- (void)toEndTapped {
    [self stopScrollForJump];
    [self stopJump];
    if (_window) {
        [self leaveWindow];
        return;
    }
    _stickToBottom = YES;
    [self scrollToBottomAnimated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self clearTextSelection];
    [self stopFollowingBottom];
    _interacting = YES;
    _scrollTargetKnown = NO;
    noshi_scroll_begin(&_scroll, scrollView.contentOffset.y, CFAbsoluteTimeGetCurrent());
    if (!_panelShown) [_input.textView resignFirstResponder];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    (void)scrollView;
    (void)velocity;
    if (!targetContentOffset) return;
    _scrollTargetKnown = YES;
    _scrollTargetOffset = targetContentOffset->y;
    [self loadOlderIfNeeded];
    [self prepareAhead:YES];
}

/* the list rests: what waited for it is let go */
- (void)scrollSettled {
    _scrollTargetKnown = NO;
    noshi_scroll_begin(&_scroll, _table.contentOffset.y, CFAbsoluteTimeGetCurrent());
    _interacting = NO;
    BOOL hadOlder = _olderDeferred;
    if (hadOlder) [self showOlder];
    else [self flushLiveMessages];
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiMessageCell class]]) ((NoshiMessageCell *)cell).activationDeferred = NO;
    }
    if (!hadOlder) [self scrollToTargetOrLoadMore];
    [self loadOlderIfNeeded];
    [self prepareAhead:YES];
    [self refreshAnimations];
    [self scheduleReplyPreviews];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    (void)scrollView;
    BOOL opens = _nextHint.progress >= 1 && _nextDialog;
    _nextHint.progress = 0;
    if (opens) {
        [self openNextChat];
        return;
    }
    [_nextDialog release];
    _nextDialog = nil;
    if (!decelerate) [self scrollSettled];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    (void)scrollView;
    [self scrollSettled];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    (void)scrollView;
    if (!_followLink) _followingBottom = NO;
    [self refreshAnimations];
}

/* the power saving settings changed, or the power saver came or went: stickers and big emoji on screen are made again, to play or to stand still, and
   the ones that may play are chosen again */
- (void)liteModeChanged {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if (path.row < 0 || (NSUInteger)path.row >= _items.count) continue;
        NoshiChatItemKind kind = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).kind;
        if (kind == NoshiChatItemSticker || kind == NoshiChatItemEmoji) [paths addObject:path];
    }
    if (paths.count) [_table reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    [self refreshAnimations];
}

/* the newest stickers on screen play, the rest rest on their first frame */
/* which stickers may run only depends on the rows on screen, and a scroll event comes sixty times a second while the same rows stay */
- (void)refreshAnimationsIfRowsChanged {
    NSArray *rows = [_table indexPathsForVisibleRows];
    NSIndexPath *first = rows.count ? [rows objectAtIndex:0] : nil, *last = rows.count ? [rows lastObject] : nil;
    if ((first ? first.row : -1) == _animatedFirst && (last ? last.row : -1) == _animatedLast) return;
    [self refreshAnimations];
}

- (void)refreshAnimations {
    if (!_visible || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        [self stopAnimations];
        return;
    }
    NSArray *rows = [_table indexPathsForVisibleRows];
    NSIndexPath *first = rows.count ? [rows objectAtIndex:0] : nil, *last = rows.count ? [rows lastObject] : nil;
    _animatedFirst = first ? first.row : -1;
    _animatedLast = last ? last.row : -1;
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiMessageCell class]] && [(NoshiMessageCell *)cell animatedSticker]) [(NoshiMessageCell *)cell setAnimating:YES];
    }
}

- (void)stopAnimations {
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiMessageCell class]]) [(NoshiMessageCell *)cell setAnimating:NO];
    }
}

- (void)messageCell:(NoshiMessageCell *)cell didDownloadMedia:(NoshiMessage *)message {
    (void)cell;
    NoshiDownloadLogAdd(_session, _dialog, message);
}

- (void)messageCell:(NoshiMessageCell *)cell didToggleQuote:(NSUInteger)quote {
    NSIndexPath *path = [_table indexPathForCell:cell];
    if (!path || (NSUInteger)path.row >= _items.count) return;
    NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)path.row];
    NSMutableIndexSet *opened = [[item.message.expandedQuotes mutableCopy] autorelease] ?: [NSMutableIndexSet indexSet];
    if ([opened containsIndex:quote]) [opened removeIndex:quote];
    else [opened addIndex:quote];
    item.message.expandedQuotes = opened;
    /* the cell that is on screen is configured again where it stands, and the table measures the row again under it */
    CGFloat from = [cell bodyHeight];
    [item invalidateLayout];
    [self configureMessageCell:cell forRow:(NSUInteger)path.row];
    [cell growBodyFromHeight:from];
    [_table beginUpdates];
    [_table endUpdates];
}

- (void)messageCellDidRevealSpoiler:(NoshiMessageCell *)cell {
    (void)cell;
    [self refreshAnimations];
}

#pragma mark reactions

- (void)closeReactionPicker {
    ++_reactionPickerToken;
    [_reactionPicker dismissAnimated:self.view.window != nil];
    [_reactionPicker release];
    _reactionPicker = nil;
    _reactionMessageId = 0;
    _reactionPickerFromMenu = NO;
}

/* a tap outside the full list: when the list came from the menu of a message, that menu comes back, with its bar of reactions, and not the bare chat */
- (void)cancelReactionPicker {
    BOOL back = _reactionPickerFromMenu;
    int32_t messageId = _reactionMessageId;
    [self closeReactionPicker];
    if (!back) return;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        if (((NoshiChatItem *)[_items objectAtIndex:i]).message.messageId != messageId) continue;
        UITableViewCell *cell = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
        if ([cell isKindOfClass:[NoshiMessageCell class]]) [self showMessageMenuForCell:(NoshiMessageCell *)cell];
        return;
    }
}

- (void)showReactionError:(NSString *)error {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"chat.reaction.failed", nil)
        message:[self failureTextForError:error] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)loadReactionChoices {
    if (!_reactionPicker) return;
    [_reactionPicker setLoading];
    NSUInteger token = ++_reactionPickerToken;
    NoshiWeakReference *weak = _weak;
    [self whenPremiumKnown:^(BOOL premium) {
    NoshiChatController *again = weak.target;
    if (!again || token != again->_reactionPickerToken || !again->_reactionPicker) return;
    /* the picker opened before the account was known as Premium or not, and its custom emoji wear locks until it is told */
    [again->_reactionPicker attachSession:again->_session media:again->_media premium:premium];
    [again->_session loadReactionChoicesForDialog:again->_dialog premium:premium completion:^(NSArray *choices, BOOL customAllowed, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || token != chat->_reactionPickerToken || !chat->_reactionPicker) return;
        [chat->_reactionPicker setCustomAllowed:customAllowed];
        if (!choices) {
            [chat->_reactionPicker setFailure:[chat failureTextForError:errorName]];
            return;
        }
        NoshiMessage *message = [chat->_server objectForKey:[NSNumber numberWithInt:chat->_reactionMessageId]];
        NSMutableArray *marked = [NSMutableArray arrayWithCapacity:choices.count];
        for (NoshiReaction *choice in choices) {
            noshi_reaction row = choice.row;
            for (NoshiReaction *current in message.reactions)
                if ([current.key isEqualToString:choice.key]) row.chosen = current.chosen;
            [marked addObject:[NoshiReaction reactionWithRow:&row]];
        }
        NSArray *ordered = [chat orderReactionChoices:marked];
        [chat->_reactionPicker setReactions:ordered];
        [chat loadCustomEmojiOfChoices:ordered];
    }];
    }];
}

/* the custom reactions the picker offers show their emoji and picture once the documents are known, and the chips are built again then */
- (void)loadCustomEmojiOfChoices:(NSArray *)choices {
    NSMutableArray *wanted = [NSMutableArray array];
    for (NoshiReaction *choice in choices) {
        if (choice.row.kind == NOSHI_REACTION_CUSTOM && choice.row.document_id) [wanted addObject:[NSNumber numberWithLongLong:choice.row.document_id]];
    }
    if (!wanted.count) return;
    NoshiWeakReference *weak = _weak;
    NSUInteger token = _reactionPickerToken;
    [NoshiCustomEmojiLoader loadDocuments:wanted session:_session media:_media documents:^(NSArray *documents) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        NSMutableDictionary *texts = [NSMutableDictionary dictionaryWithCapacity:documents.count];
        for (NoshiCustomEmojiDocument *document in documents) [texts setObject:document.alt forKey:[NSNumber numberWithLongLong:document.documentId]];
        [NoshiReaction rememberCustomTexts:texts];
        if (token == chat->_reactionPickerToken && chat->_reactionPicker) [chat->_reactionPicker setReactions:choices];
    } picture:^{
        NoshiChatController *chat = weak.target;
        if (chat && token == chat->_reactionPickerToken && chat->_reactionPicker) NoshiRedrawTree(chat->_reactionPicker);
    }];
}

/* whether the account has Telegram Premium, asked once; custom emoji in the panel and in the reaction choices depend on it */
- (void)whenPremiumKnown:(void (^)(BOOL premium))block {
    if (_premiumKnown) {
        block(_premium);
        return;
    }
    void (^then)(BOOL) = [block copy];
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        NoshiPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (chat && me) {
            chat->_premium = me.premium;
            chat->_serverPremium = me.premium;
            chat->_premiumKnown = YES;
        } else if (!me) {
            NSLog(@"noshigram: premium state unknown: %@", errorName);
        }
        if (chat) then(me.premium);
        [then release];
    }];
}

- (void)addSongToProfile:(NoshiMedia *)song {
    [self retain];
    [_session saveMusic:song unsave:NO completion:^(NSString *errorName) {
        [self autorelease];
        if (errorName) {
            NSLog(@"noshigram: song not saved to the profile: %@", errorName);
            NoshiGiftAlert(nil, [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                         : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]);
            return;
        }
        NoshiGiftAlert(nil, NSLocalizedString(@"music.added", nil));
    }];
}

- (void)messageCellDidLongPress:(NoshiMessageCell *)cell {
    [self showMessageMenuForCell:cell];
}

/* the bubble of a message that is on screen, in the coordinates of the chat view; empty when its row is out of sight */
- (CGRect)visibleBubbleOfMessageId:(int32_t)messageId {
    for (NSUInteger i = 0; i < _items.count; ++i) {
        NoshiChatItem *item = [_items objectAtIndex:i];
        if (item.message.messageId != messageId) continue;
        UITableViewCell *cell = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
        if (!cell) return CGRectZero;
        CGRect bubble = CGRectIntersection([self.view convertRect:item.bubbleFrame fromView:cell.contentView], _table.frame);
        return CGRectIsNull(bubble) ? CGRectZero : bubble;
    }
    return CGRectZero;
}

- (void)showReactionPickerForMessage:(NoshiMessage *)message {
    if (message.messageId <= 0 || !message.reactionsPossible || [self reactionsHidden]) return;
    [self dismissInput];
    [self closeReactionPicker];
    _reactionMessageId = message.messageId;
    _reactionPicker = [[NoshiReactionPicker alloc] initWithFrame:self.view.bounds];
    _reactionPicker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _reactionPicker.anchorRect = [self visibleBubbleOfMessageId:message.messageId];
    _reactionPicker.anchorOutgoing = message.outgoing;
    [_reactionPicker attachSession:_session media:_media premium:_premiumKnown && _premium];
    NoshiWeakReference *weak = _weak;
    _reactionPicker.cancelHandler = ^{ [(NoshiChatController *)weak.target cancelReactionPicker]; };
    _reactionPicker.retryHandler = ^{ [(NoshiChatController *)weak.target loadReactionChoices]; };
    _reactionPicker.pickHandler = ^(NoshiReaction *reaction) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        int32_t messageId = chat->_reactionMessageId;
        [chat closeReactionPicker];
        [chat chooseReaction:reaction messageId:messageId burst:NOSHI_BURST_LONG];
    };
    _reactionPicker.customPickHandler = ^(NoshiCustomEmojiDocument *emoji) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        int32_t messageId = chat->_reactionMessageId;
        if (!chat->_premiumKnown || !chat->_premium) {
            NoshiGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil));
            return;
        }
        noshi_reaction row;
        memset(&row, 0, sizeof(row));
        row.kind = NOSHI_REACTION_CUSTOM;
        row.document_id = emoji.documentId;
        NoshiReaction *reaction = [NoshiReaction reactionWithRow:&row];
        /* the chip that shows the choice needs the emoji the document stands for */
        if (emoji.alt.length) [NoshiReaction rememberCustomTexts:[NSDictionary dictionaryWithObject:emoji.alt forKey:[NSNumber numberWithLongLong:emoji.documentId]]];
        [chat closeReactionPicker];
        [chat chooseReaction:reaction messageId:messageId burst:NOSHI_BURST_NONE];
    };
    [self.view addSubview:_reactionPicker];
    [self loadReactionChoices];
}

- (BOOL)reactionIsChosen:(NoshiReaction *)reaction messageId:(int32_t)messageId {
    NoshiMessage *message = [_server objectForKey:[NSNumber numberWithInt:messageId]];
    for (NoshiReaction *current in message.reactions) if (current.chosen && [current.key isEqualToString:reaction.key]) return YES;
    return NO;
}

/* the chip of a reaction on a message that is on screen, in the coordinates of the chat view; empty when the row is out of sight */
- (CGRect)chipFrameOfReaction:(NoshiReaction *)reaction messageId:(int32_t)messageId {
    for (NSUInteger i = 0; i < _items.count; ++i) {
        if (((NoshiChatItem *)[_items objectAtIndex:i]).message.messageId != messageId) continue;
        NoshiMessageCell *cell = (NoshiMessageCell *)[_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
        if (![cell isKindOfClass:[NoshiMessageCell class]]) return CGRectZero;
        [cell layoutIfNeeded];
        return [cell chipFrameOfReaction:reaction inView:self.view];
    }
    return CGRectZero;
}

/* the burst of a reaction that is put on a message and was not there; taking one back plays nothing */
- (void)playReactionEffectFor:(NoshiReaction *)reaction messageId:(int32_t)messageId longBurst:(BOOL)longBurst chip:(CGRect)chip {
    if (reaction.row.kind != NOSHI_REACTION_EMOJI) return;
    if ([self reactionIsChosen:reaction messageId:messageId]) return;
    NoshiReactionArtwork *artwork = [NoshiReactionArtwork artForEmoji:reaction.emoji];
    if (!artwork) return;
    CGRect bubble = [self visibleBubbleOfMessageId:messageId];
    /* a tap on a chip bursts from the picture of that chip, which stands at its left end; the picker has no chip yet, so it bursts over the bubble */
    CGPoint center;
    if (!CGRectIsNull(CGRectIntersection(chip, _table.frame)) && !CGRectIsEmpty(chip)) center = CGPointMake(CGRectGetMinX(chip) + CGRectGetHeight(chip) / 2, CGRectGetMidY(chip));
    else if (CGRectIsEmpty(bubble)) center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    else center = CGPointMake(CGRectGetMidX(bubble), CGRectGetMidY(bubble));
    [NoshiReactionEffect playArtwork:artwork longBurst:longBurst around:center inView:self.view media:_media];
}

/* the chips were built before the server's icons were known */
- (void)reactionArtworkLoaded {
    /* one icon lands after another when the chat opens, and each used to rebuild every row on the spot */
    [self scheduleLiveMessages];
}

- (void)chooseReaction:(NoshiReaction *)reaction messageId:(int32_t)messageId burst:(int)burst {
    NSNumber *key = [NSNumber numberWithInt:messageId];
    NoshiMessage *message = [_server objectForKey:key];
    if (!message || !message.reactionsPossible || [self reactionsHidden] || [_reactionSending containsObject:key]) return;
    /* a paid reaction is a star taken from the balance, so the person is asked first */
    if (reaction.row.kind == NOSHI_REACTION_PAID) {
        [self confirmPaidReactionToMessageId:messageId];
        return;
    }
    /* a custom emoji is a reaction only for an account with Premium: while that is not known the answer is waited for instead of the choice being refused, and a chip we already
       chose can always be taken back */
    if (reaction.row.kind == NOSHI_REACTION_CUSTOM && !reaction.chosen && !(_premiumKnown && _premium)) {
        NoshiWeakReference *weak = _weak;
        [self whenPremiumKnown:^(BOOL premium) {
            NoshiChatController *chat = weak.target;
            if (!chat) return;
            if (!premium) { NoshiGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil)); return; }
            [chat chooseReaction:reaction messageId:messageId burst:burst];
        }];
        return;
    }
    BOOL removing = NO;
    NSMutableArray *chosen = [NSMutableArray array];
    for (NoshiReaction *current in message.reactions) {
        if (!current.chosen || current.row.kind == NOSHI_REACTION_PAID) continue;
        if ([current.key isEqualToString:reaction.key]) removing = YES;
        else [chosen addObject:current];
    }
    if (removing) {
        /* taking a chip back keeps the choices made in other clients, in the order they were chosen */
        [chosen sortUsingComparator:^NSComparisonResult(NoshiReaction *a, NoshiReaction *b) {
            return a.row.chosen_order < b.row.chosen_order ? NSOrderedAscending :
                (a.row.chosen_order > b.row.chosen_order ? NSOrderedDescending : NSOrderedSame);
        }];
        [self sendReactionChoices:chosen messageId:messageId picked:nil burst:NOSHI_BURST_NONE];
        return;
    }
    /* the limit depends on Premium and on the server's numbers, so a tap waits for both once */
    NoshiWeakReference *weak = _weak;
    [_reactionSending addObject:key];
    [self whenPremiumKnown:^(BOOL premium) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat whenReactionLimitsKnown:^(int32_t standard, int32_t premiumLimit) {
            NoshiChatController *again = weak.target;
            if (!again) return;
            [again->_reactionSending removeObject:key];
            /* the server counts the limit by the real Premium, so the local one must not raise it: the server answers REACTIONS_TOO_MANY to a second reaction of a free account */
            BOOL serverPremium = again->_serverPremium;
            [again chooseReaction:reaction among:chosen limit:serverPremium ? premiumLimit : standard premium:serverPremium messageId:messageId burst:burst];
        }];
    }];
}

/* the ordinary reactions already chosen stay while the account's limit allows; the oldest make room for the new one */
- (void)chooseReaction:(NoshiReaction *)reaction among:(NSArray *)chosen limit:(int32_t)limit premium:(BOOL)premium messageId:(int32_t)messageId burst:(int)burst {
    if (limit < 1) limit = 1;
    noshi_reaction rows[NOSHI_REACTIONS_MAX], plan[NOSHI_REACTIONS_MAX];
    size_t count = MIN(chosen.count, (NSUInteger)NOSHI_REACTIONS_MAX);
    for (size_t i = 0; i < count; ++i) rows[i] = [(NoshiReaction *)[chosen objectAtIndex:i] row];
    noshi_reaction pick = reaction.row;
    size_t planned = noshi_reaction_choices_after_pick(rows, count, &pick, (size_t)limit, plan, NOSHI_REACTIONS_MAX);
    if (!planned) {
        NSLog(@"noshigram: reaction choice of message %d rejected, %lu chosen, limit %d", messageId, (unsigned long)chosen.count, limit);
        return;
    }
    NSMutableArray *choices = [NSMutableArray arrayWithCapacity:planned];
    for (size_t i = 0; i < planned; ++i) {
        NoshiReaction *entry = noshi_reaction_equal(&plan[i], &pick) ? reaction : nil;
        for (NoshiReaction *current in chosen) {
            noshi_reaction row = current.row;
            if (!entry && noshi_reaction_equal(&plan[i], &row)) entry = current;
        }
        [choices addObject:entry];
    }
    /* a free account keeps one reaction, so a second tap replaces the first; the plate says once that Premium keeps more */
    if (!premium && chosen.count == 1 && limit == 1) [self showMultipleReactionsPromo];
    [self sendReactionChoices:choices messageId:messageId picked:reaction burst:burst];
}

/* the server's numbers, asked once per screen; a failed answer leaves the documented 1 and 3 in place and the next tap asks again */
- (void)whenReactionLimitsKnown:(void (^)(int32_t standard, int32_t premium))block {
    if (_reactionLimitsKnown) {
        block(_reactionLimitStandard, _reactionLimitPremium);
        return;
    }
    void (^then)(int32_t, int32_t) = [block copy];
    NoshiWeakReference *weak = _weak;
    [_session loadReactionLimits:^(int32_t standard, int32_t premium, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (chat) {
            chat->_reactionLimitStandard = standard;
            chat->_reactionLimitPremium = premium;
            chat->_reactionLimitsKnown = errorName == nil;
        }
        if (errorName) NSLog(@"noshigram: reaction limits not taken, using %d and %d: %@", standard, premium, errorName);
        then(standard, premium);
        [then release];
    }];
}

#define NOSHI_MULTIPLE_REACTIONS_PROMO_KEY @"noshigram.reactions.multiplePromoShown"

/* the plate of exteraGram's showMultipleReactionsPromo: shown the first time a free account picks a second reaction, never again */
- (void)showMultipleReactionsPromo {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:NOSHI_MULTIPLE_REACTIONS_PROMO_KEY]) return;
    [defaults setBool:YES forKey:NOSHI_MULTIPLE_REACTIONS_PROMO_KEY];
    [_reactionPromo release];
    _reactionPromo = [[NoshiWelcomeToast alloc] init];
    _reactionPromo.messageText = NSLocalizedString(@"chat.reaction.multiple", nil);
    _reactionPromo.lifetime = 5;
    NoshiWeakReference *weak = _weak;
    _reactionPromo.dismissHandler = ^{
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat->_reactionPromo release];
        chat->_reactionPromo = nil;
    };
    [_reactionPromo showInView:self.view.window ? self.view.window : self.view inset:NoshiStatusBarHeight()];
}

- (NSString *)reactionFrequencyKey {
    long long account = [NoshiSession accountIdInDirectory:_session.directory];
    return account > 0 ? [NSString stringWithFormat:@"noshigram.reactions.frequency.%lld", account] : nil;
}

- (NSArray *)orderReactionChoices:(NSArray *)choices {
    NSString *key = [self reactionFrequencyKey];
    NSDictionary *counts = key ? [[NSUserDefaults standardUserDefaults] dictionaryForKey:key] : nil;
    NSMutableDictionary *positions = [NSMutableDictionary dictionaryWithCapacity:choices.count];
    for (NSUInteger i = 0; i < choices.count; ++i) {
        NSString *reactionKey = ((NoshiReaction *)[choices objectAtIndex:i]).key;
        if (reactionKey && ![positions objectForKey:reactionKey]) [positions setObject:[NSNumber numberWithUnsignedInteger:i] forKey:reactionKey];
    }
    return [choices sortedArrayUsingComparator:^NSComparisonResult(NoshiReaction *a, NoshiReaction *b) {
        NSUInteger left = [[counts objectForKey:a.key] unsignedIntegerValue], right = [[counts objectForKey:b.key] unsignedIntegerValue];
        if (left != right) return left > right ? NSOrderedAscending : NSOrderedDescending;
        NSUInteger first = [[positions objectForKey:a.key] unsignedIntegerValue], second = [[positions objectForKey:b.key] unsignedIntegerValue];
        return first < second ? NSOrderedAscending : (first > second ? NSOrderedDescending : NSOrderedSame);
    }];
}

- (void)rememberReaction:(NoshiReaction *)reaction {
    NSString *key = [self reactionFrequencyKey];
    if (!key || !reaction.key.length) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *stored = [defaults dictionaryForKey:key];
    NSMutableDictionary *counts = stored ? [NSMutableDictionary dictionaryWithDictionary:stored] : [NSMutableDictionary dictionary];
    NSUInteger count = [[counts objectForKey:reaction.key] unsignedIntegerValue];
    [counts setObject:[NSNumber numberWithUnsignedInteger:MIN(count, (NSUInteger)999999) + 1] forKey:reaction.key];
    if (counts.count > 128) {
        NSString *least = nil;
        for (NSString *candidate in counts) if (!least || [[counts objectForKey:candidate] unsignedIntegerValue] < [[counts objectForKey:least] unsignedIntegerValue]) least = candidate;
        if (least) [counts removeObjectForKey:least];
    }
    [defaults setObject:counts forKey:key];
}

- (void)sendReactionChoices:(NSArray *)choices messageId:(int32_t)messageId picked:(NoshiReaction *)picked burst:(int)burst {
    NSNumber *key = [NSNumber numberWithInt:messageId];
    if ([_reactionSending containsObject:key]) return;
    [_reactionSending addObject:key];
    /* the burst belongs to a chip that was not chosen before, and it waits for the answer because the chip does not exist until then */
    BOOL playBurst = burst != NOSHI_BURST_NONE && picked && ![self reactionIsChosen:picked messageId:messageId];
    NoshiWeakReference *weak = _weak;
    [_session sendReactions:choices messageId:messageId dialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat->_reactionSending removeObject:key];
        if (errorName) {
            NSLog(@"noshigram: sending reaction to chat %lld message %d failed: %@", chat->_dialog.peerId, messageId, errorName);
            if (chat->_visible) [chat showReactionError:errorName];
            return;
        }
        if (picked) [chat rememberReaction:picked];
        [chat mergeMessages:messages];
        [chat rebuildItems];
        if (playBurst) [chat playReactionEffectFor:picked messageId:messageId longBurst:burst == NOSHI_BURST_LONG chip:[chat chipFrameOfReaction:picked messageId:messageId]];
    }];
}

/* one star for a tap, after the person agreed to it */
- (void)confirmPaidReactionToMessageId:(int32_t)messageId {
    NSNumber *key = [NSNumber numberWithInt:messageId];
    if ([_reactionSending containsObject:key]) return;
    NoshiWeakReference *weak = _weak;
    NoshiShowAlert(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.reaction.paid.confirm", nil), 1],
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"chat.reaction.paid.send", nil), nil], 0, NO,
                     ^(NSInteger index, NSString *text) {
        (void)text;
        NoshiChatController *chat = weak.target;
        if (!chat || index != 1 || [chat->_reactionSending containsObject:key]) return;
        [chat->_reactionSending addObject:key];
        [chat->_session sendPaidReactionOfStars:1 messageId:messageId dialog:chat->_dialog completion:^(NSArray *messages, NSString *errorName) {
            NoshiChatController *again = weak.target;
            if (!again) return;
            [again->_reactionSending removeObject:key];
            if (errorName) {
                NSLog(@"noshigram: sending a paid reaction to message %d failed: %@", messageId, errorName);
                if (again->_visible) [again showReactionError:errorName];
                return;
            }
            [again mergeMessages:messages];
            [again rebuildItems];
        }];
    });
}

/* a private chat has two people, so who reacted needs no list: the hold on a chip tells when it was put, as Telegram does */
- (BOOL)messageCellShowsReactionTime:(NoshiMessageCell *)cell {
    (void)cell;
    return (_dialog.kind == NOSHI_DIALOG_USER || _dialog.kind == NOSHI_DIALOG_BOT) && !_dialog.saved;
}

- (void)messageCell:(NoshiMessageCell *)cell didHoldReaction:(NoshiReaction *)reaction {
    NoshiMessage *message = cell.item.message;
    if (!message || message.messageId <= 0) return;
    NoshiWeakReference *weak = _weak;
    NSString *key = [[reaction.key copy] autorelease];
    NoshiReaction *shown = [reaction retain];
    [_session loadReactorsOfMessageId:message.messageId ofDialog:_dialog offset:nil completion:^(NSArray *items, NSDictionary *people, NSString *next, NSString *errorName) {
        (void)next;
        NoshiChatController *chat = weak.target;
        [shown autorelease];
        if (!chat) return;
        if (errorName) {
            NoshiShowNotice(nil, [chat failureTextForError:errorName]);
            return;
        }
        NSMutableArray *entries = [NSMutableArray array];
        for (NSDictionary *item in items) {
            if (![[(NoshiReaction *)[item objectForKey:@"reaction"] key] isEqualToString:key]) continue;
            NSNumber *peer = [item objectForKey:@"peer"];
            NoshiPerson *person = [people objectForKey:peer];
            if (!person) person = [chat->_people objectForKey:peer];
            if (!person) {
                NoshiPerson *own = [chat->_session ownPerson];
                if (own && own.userId == peer.longLongValue) person = own;
            }
            if (!person) continue;
            [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:person, @"person", [item objectForKey:@"date"], @"date", nil]];
        }
        if (!entries.count) return;
        [NoshiReactionTimePopup presentReaction:shown entries:entries avatars:chat->_avatars inView:NoshiOverlayHost()];
    }];
}

- (void)messageCell:(NoshiMessageCell *)cell didTapReaction:(NoshiReaction *)reaction {
    /* the chip is already there, so the burst starts at once from its picture */
    [self playReactionEffectFor:reaction messageId:cell.item.message.messageId longBurst:NO chip:[cell chipFrameOfReaction:reaction inView:self.view]];
    [self chooseReaction:reaction messageId:cell.item.message.messageId burst:NOSHI_BURST_NONE];
}

#pragma mark polls

/* the polls on screen that can still change are asked for again with the reactions, so the counts move while the chat is open */
- (void)pollPolls {
    if (_pollingPolls || !_visible || !_loadedFirst || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        NoshiMessage *message = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if (message.messageId > 0 && message.poll && !message.poll.closed && ![_votingPolls containsObject:key]) [ids addObject:key];
        if (ids.count == NOSHI_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    _pollingPolls = YES;
    [self refreshPollsOfMessageIds:ids];
}

/* the server's copy of the polls replaces what the messages carry when the counts or the votes differ; the picks not yet sent carry over */
- (void)refreshPollsOfMessageIds:(NSArray *)ids {
    NoshiWeakReference *weak = _weak;
    [_session loadMessagesWithIds:ids ofDialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_pollingPolls = NO;
        if (!messages) {
            NSLog(@"noshigram: the polls did not refresh: %@", errorName);
            return;
        }
        BOOL changed = NO;
        for (NoshiMessage *fresh in messages) {
            NoshiMessage *current = [chat->_server objectForKey:[NSNumber numberWithInt:fresh.messageId]];
            if (!current || !current.poll || !fresh.poll || [chat->_votingPolls containsObject:[NSNumber numberWithInt:fresh.messageId]]) continue;
            [fresh.poll inheritPickedFrom:current.poll];
            if ([fresh.poll.stateKey isEqualToString:current.poll.stateKey]) continue;
            current.poll = fresh.poll;
            changed = YES;
        }
        if (!changed || !chat->_visible) return;
        [chat rebuildItems];
    }];
}

- (void)votePollOfMessage:(NoshiMessage *)message options:(NSArray *)tokens {
    NSNumber *key = [NSNumber numberWithInt:message.messageId];
    if ([_votingPolls containsObject:key]) return;
    if (!_votingPolls) _votingPolls = [[NSMutableSet alloc] init];
    [_votingPolls addObject:key];
    NoshiWeakReference *weak = _weak;
    [_session sendVoteOptions:tokens forMessageId:message.messageId ofDialog:_dialog completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat->_votingPolls removeObject:key];
        if (errorName) {
            NSLog(@"noshigram: the vote in message %@ was not taken: %@", key, errorName);
            NoshiGiftAlert(NSLocalizedString(@"poll.failed", nil), NoshiGiftErrorText(errorName));
            return;
        }
        /* the vote is in; the picks are spent and the counts come from the server */
        NoshiMessage *current = [chat messageWithId:key.intValue];
        [current.poll clearPicked];
        chat->_pollingPolls = YES;
        [chat refreshPollsOfMessageIds:[NSArray arrayWithObject:key]];
    }];
}

/* a tap on an answer votes for it, or marks it in a poll with several answers; the button under the answers sends the marks or takes the vote back */
- (void)messageCell:(NoshiMessageCell *)cell didTapPollAnswer:(NSInteger)index {
    NoshiMessage *message = cell.item.message;
    NoshiPoll *poll = message.poll;
    if (!poll || message.messageId <= 0 || _pinnedList) return;
    if (poll.closed) {
        [self toast:NSLocalizedString(@"poll.closed", nil)];
        return;
    }
    if (index < 0) {
        if (poll.voted) {
            [self votePollOfMessage:message options:[NSArray array]];
            return;
        }
        NSMutableArray *tokens = [NSMutableArray array];
        [poll.picked enumerateIndexesUsingBlock:^(NSUInteger at, BOOL *stop) {
            (void)stop;
            if (at < poll.answers.count) [tokens addObject:((NoshiPollAnswer *)[poll.answers objectAtIndex:at]).option];
        }];
        if (tokens.count) [self votePollOfMessage:message options:tokens];
        return;
    }
    if ((NSUInteger)index >= poll.answers.count) return;
    NoshiPollAnswer *answer = [poll.answers objectAtIndex:(NSUInteger)index];
    if (poll.voted) {
        /* a quiz and a poll that forbids it keep the first answer, and one with several answers is changed from the button */
        if (poll.quiz || poll.revotingDisabled || poll.multiple) return;
        [self votePollOfMessage:message options:answer.chosen ? [NSArray array] : [NSArray arrayWithObject:answer.option]];
        return;
    }
    if (poll.multiple) {
        [poll togglePicked:(NSUInteger)index];
        [self rebuildItems];
        return;
    }
    [self votePollOfMessage:message options:[NSArray arrayWithObject:answer.option]];
}

- (void)pollReactions {
    [self pollPolls];
    if (!_visible || !_loadedFirst || _pollingReactions || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        NoshiMessage *message = ((NoshiChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if (message.messageId > 0 && !message.outgoing && message.hasReactions && ![_reactionSending containsObject:key]) [ids addObject:key];
        if (ids.count == NOSHI_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    _pollingReactions = YES;
    NoshiWeakReference *weak = _weak;
    [_session refreshReactionsForMessages:ids dialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_pollingReactions = NO;
        if (!messages) { NSLog(@"noshigram: polling reactions failed: %@", errorName); return; }
        if (!chat->_visible) return;
        BOOL changed = NO;
        for (NoshiMessage *message in messages) {
            NSNumber *key = [NSNumber numberWithInt:message.messageId];
            NoshiMessage *previous = [chat->_server objectForKey:key];
            if (previous && ![previous.reactionKey isEqualToString:message.reactionKey] && ![chat->_reactionSending containsObject:key]) {
                [chat->_server setObject:message forKey:key];
                changed = YES;
            }
        }
        if (changed) {
            [chat rebuildItems];
        }
    }];
}

#pragma mark sending

- (long long)newRandomId {
    long long random;
    do {
        random = (long long)(((uint64_t)arc4random() << 32 | arc4random()) & 0x7fffffffffffffffULL);
    } while (random == 0);
    return random;
}

#pragma mark attaching

- (void)inputBarDidTapAttach:(NoshiInputBar *)bar {
    (void)bar;
    [self.view endEditing:YES];
    NoshiAttachSheet *sheet = [[[NoshiAttachSheet alloc] init] autorelease];
    sheet.delegate = self;
    sheet.offersGift = [self canReceiveGift];
    [sheet showInView:self.view];
}

- (void)attachSheet:(NoshiAttachSheet *)sheet didChoose:(NoshiAttachChoice)choice {
    (void)sheet;
    [self attachFlow];
    switch (choice) {
    case NoshiAttachGallery: [_attach chooseGallery]; break;
    case NoshiAttachFile: [_attach chooseFile]; break;
    case NoshiAttachLocation: [_attach chooseLocation]; break;
    case NoshiAttachGift: [self openGiftCatalog]; break;
    case NoshiAttachContact: [_attach chooseContact]; break;
    case NoshiAttachCamera: [_attach chooseCamera]; break;
    }
}

- (void)attachSheet:(NoshiAttachSheet *)sheet didChooseAssets:(NSArray *)urls options:(NoshiAttachOptions *)options {
    (void)sheet;
    /* the caption field of the sheet may still hold the keyboard, and the screen that opens over it would come up with the keys over its lower half */
    [self.view endEditing:YES];
    [[self attachFlow] chooseAssets:urls options:options];
}

#pragma mark message actions

/* one line that says what a message is, for the strip and the details */
static NSString *NoshiMessageSummary(NoshiMessage *message) {
    if (message.text.length) return message.text;
    switch (message.media.kind) {
    case NOSHI_PREVIEW_PHOTO: return NSLocalizedString(@"preview.photo", nil);
    case NOSHI_PREVIEW_VIDEO: return NSLocalizedString(@"preview.video", nil);
    case NOSHI_PREVIEW_VIDEO_MESSAGE: return NSLocalizedString(@"preview.videomessage", nil);
    case NOSHI_PREVIEW_VOICE: return NSLocalizedString(@"preview.voice", nil);
    case NOSHI_PREVIEW_AUDIO: return NSLocalizedString(@"preview.audio", nil);
    case NOSHI_PREVIEW_STICKER: return NSLocalizedString(@"preview.sticker", nil);
    case NOSHI_PREVIEW_GIF: return NSLocalizedString(@"preview.gif", nil);
    /* a file is told by its name, as the row in the chat tells it */
    case NOSHI_PREVIEW_FILE: return message.media.name.length ? message.media.name : NSLocalizedString(@"preview.file", nil);
    case NOSHI_PREVIEW_LOCATION: return NSLocalizedString(@"preview.location", nil);
    case NOSHI_PREVIEW_CONTACT: return NSLocalizedString(@"preview.contact", nil);
    case NOSHI_PREVIEW_POLL: return NSLocalizedString(@"preview.poll", nil);
    default: break;
    }
    return NSLocalizedString(@"preview.message", nil);
}

- (NSString *)senderNameOfMessage:(NoshiMessage *)message {
    if (message.outgoing) return NSLocalizedString(@"chat.msg.you", nil);
    if (message.post) return _dialog.title;
    NSString *name = [[_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]] name];
    return name.length ? name : (_dialog.kind == NOSHI_DIALOG_USER || _dialog.kind == NOSHI_DIALOG_BOT ? _dialog.title : NSLocalizedString(@"chat.someone", nil));
}

/* the setting hides the reactions of one kind of chat: the chips, the pill of the menu and the reaction itself */
- (BOOL)reactionsHidden {
    /* the reactions of the favorites are tags, which the server takes from Premium accounts only and answers REACTION_INVALID to the rest */
    if (_dialog.saved) return !(_premiumKnown && _premium);
    switch (_dialog.kind) {
    case NOSHI_DIALOG_USER:
    case NOSHI_DIALOG_BOT: return NoshiChatFlagGet(NoshiChatFlagHideReactionsPrivate);
    case NOSHI_DIALOG_GROUP: return NoshiChatFlagGet(NoshiChatFlagHideReactionsGroups);
    case NOSHI_DIALOG_CHANNEL: return NoshiChatFlagGet(NoshiChatFlagHideReactionsChannels);
    }
    return NO;
}

- (noshi_action_context)actionContextOfMessage:(NoshiMessage *)message {
    noshi_action_context context;
    memset(&context, 0, sizeof(context));
    context.peer_kind = _dialog.peerKind;
    context.message_id = message.messageId;
    context.broadcast = _dialog.kind == NOSHI_DIALOG_CHANNEL;
    context.can_post = _channelFull ? _channelFull.dialog.canPost : _dialog.canPost;
    context.admin = _channelFull ? _channelFull.dialog.admin : _dialog.admin;
    context.can_view_stats = _channelFull.canViewStats;
    context.music_saveable = message.media.kind == NOSHI_PREVIEW_AUDIO && message.media.file && message.media.ref.ref_len;
    context.forwarded = message.forwarded;
    context.views = message.views;
    context.forwards = message.forwards;
    context.outgoing = message.outgoing;
    context.service = message.service;
    context.has_text = message.text.length > 0;
    context.has_entities = message.entities.count > 0;
    context.media = message.media.kind;
    context.reactions_possible = message.reactionsPossible && ![self reactionsHidden];
    NoshiPerson *sender = message.outgoing ? nil : [_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    context.sender_user = sender && sender.userId > 0 && sender.accessHash != 0;
    context.has_username = _channelFull.username.length > 0;
    context.pinned_now = _pinnedId && _pinnedId == message.messageId;
    context.saved_chat = _dialog.saved;
    context.media_fetchable = message.media.file != nil;
    context.translate_wanted = [self translateWantedForMessage:message];
    context.bookmarked = [[NoshiBookmarks bookmarksForSession:_session] containsMessageId:message.messageId inDialog:_dialog];
    return context;
}

typedef struct { uint32_t action; NoshiSymbol symbol; NSString *key; BOOL destructive; } NoshiMessageActionRow;

/* the black strip over the message, the actions of one tap as telegram for ios 4 had them, with the translation among them and the start of a selection at the end */
static const NoshiMessageActionRow NoshiMessageActionIcons[] = {
    {NOSHI_ACTION_REPLY, NoshiSymbolReply, @"chat.msg.reply", NO},
    {NOSHI_ACTION_COPY, NoshiSymbolCopy, @"chat.msg.copy", NO},
    {NOSHI_ACTION_TRANSLATE, NoshiSymbolTranslate, @"tr.translate", NO},
    {NOSHI_ACTION_SELECT, NoshiSymbolCheck, @"chat.msg.select", NO},
};

/* the buttons of the white sheet at the bottom, forwarding, reporting and deleting last as in telegram for ios 4 */
static const NoshiMessageActionRow NoshiMessageActionRows[] = {
    {NOSHI_ACTION_EDIT, NoshiSymbolCompose, @"chat.msg.edit", NO},
    {NOSHI_ACTION_PIN, NoshiSymbolPin, @"chat.msg.pin", NO},
    {NOSHI_ACTION_UNPIN, NoshiSymbolUnpin, @"chat.msg.unpin", NO},
    {NOSHI_ACTION_SAVE_MUSIC, NoshiSymbolMusic, @"music.add", NO},
    {NOSHI_ACTION_STATISTICS, NoshiSymbolStatistics, @"chat.msg.stats", NO},
    {NOSHI_ACTION_COPY_LINK, NoshiSymbolLink, @"profile.qr.copy", NO},
    {NOSHI_ACTION_GALLERY, NoshiSymbolGallery, @"media.save", NO},
    {NOSHI_ACTION_TRANSCRIBE, NoshiSymbolMicrophone, @"chat.msg.transcribe", NO},
    {NOSHI_ACTION_BOOKMARK, NoshiSymbolStar, @"chat.msg.bookmark", NO},
    {NOSHI_ACTION_UNBOOKMARK, NoshiSymbolStar, @"chat.msg.unbookmark", NO},
    {NOSHI_ACTION_SAVE, NoshiSymbolBookmark, @"chat.msg.save", NO},
    {NOSHI_ACTION_FORWARD_HIDDEN, NoshiSymbolEyeSlash, @"chat.msg.forwardhidden", NO},
    {NOSHI_ACTION_COPY_PHOTO, NoshiSymbolGallery, @"chat.msg.copyphoto", NO},
    {NOSHI_ACTION_REPEAT, NoshiSymbolRepeat, @"chat.msg.repeat", NO},
    {NOSHI_ACTION_HISTORY, NoshiSymbolMagnifier, @"chat.msg.history", NO},
    {NOSHI_ACTION_SELECT_TEXT, NoshiSymbolCopy, @"chat.msg.selecttext", NO},
    {NOSHI_ACTION_REPLY_PRIVATE, NoshiSymbolChats, @"chat.msg.replyprivate", NO},
    {NOSHI_ACTION_REMIND, NoshiSymbolClock, @"chat.msg.remind", NO},
    {NOSHI_ACTION_DETAILS, NoshiSymbolInfo, @"chat.msg.details", NO},
    {NOSHI_ACTION_FORWARD, NoshiSymbolForward, @"chat.msg.forward", NO},
    {NOSHI_ACTION_REPORT, NoshiSymbolReport, @"chat.msg.report", YES},
    {NOSHI_ACTION_DELETE, NoshiSymbolTrash, @"chat.msg.delete", YES},
};

static NSArray *NoshiMenuItems(const NoshiMessageActionRow *table, size_t count, uint32_t mask) {
    NSMutableArray *items = [NSMutableArray array];
    for (size_t i = 0; i < count; ++i) {
        if (!(mask & table[i].action)) continue;
        [items addObject:[NoshiMenuItem itemWithTitle:NSLocalizedString(table[i].key, nil) symbol:table[i].symbol tag:table[i].action destructive:table[i].destructive]];
    }
    return items;
}

/* the reactions of the pill, marked with the ones this message already carries from us. The pill shows the first of them, so they stand in the order of the full panel: the
   ones the person used most come first, and the server's order only settles a tie */
- (NSArray *)menuReactionsForMessage:(NoshiMessage *)message {
    NSMutableArray *marked = [NSMutableArray array];
    for (NoshiReaction *choice in [self orderReactionChoices:_menuReactions]) {
        if (choice.row.kind != NOSHI_REACTION_EMOJI) continue;
        noshi_reaction row = choice.row;
        row.chosen = 0;
        for (NoshiReaction *current in message.reactions) if ([current.key isEqualToString:choice.key]) row.chosen = current.chosen;
        [marked addObject:[NoshiReaction reactionWithRow:&row]];
    }
    return marked;
}

/* the reactions the chat offers are asked for once and kept, so the next menu has its pill at once */
- (void)loadMenuReactionsThen:(void (^)(void))then {
    if (_menuReactions || _menuReactionsLoading) return;
    _menuReactionsLoading = YES;
    NoshiWeakReference *weak = _weak;
    [self whenPremiumKnown:^(BOOL premium) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        [chat->_session loadReactionChoicesForDialog:chat->_dialog premium:premium completion:^(NSArray *choices, BOOL customAllowed, NSString *errorName) {
            NoshiChatController *again = weak.target;
            if (!again) return;
            again->_menuReactionsLoading = NO;
            again->_menuCustomAllowed = customAllowed;
            if (!choices) {
                NSLog(@"noshigram: the reactions for the menu did not load: %@", errorName);
                return;
            }
            again->_menuReactions = [choices copy];
            if (then) then();
        }];
    }];
}

- (void)fillReadersPage:(NoshiSettingsPageController *)page readers:(NSArray *)readers people:(NSDictionary *)people {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *reader in readers) {
        NSNumber *user = [reader objectForKey:@"user"];
        NoshiPerson *person = [people objectForKey:user];
        NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", user];
        int32_t date = [[reader objectForKey:@"date"] intValue];
        NSString *time = date > 0 ? NoshiMediaTimeText(date) : NSLocalizedString(@"chat.msg.readtime.unavailable", nil);
        NoshiReaderRowView *view = [[[NoshiReaderRowView alloc] initWithPerson:person userId:user.longLongValue name:name time:time cache:_avatars] autorelease];
        [rows addObject:[NoshiSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { (void)width; return 64; }]];
    }
    page.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:rows]];
    [page reloadSettings];
}

- (void)showMessageMenuForCell:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    noshi_action_context context = [self actionContextOfMessage:message];
    uint32_t mask = noshi_message_actions_for(&context);
    /* a list of search results or pinned messages has no field to give way to the bar, so nothing is picked there */
    if (_pinnedList) mask &= ~(uint32_t)NOSHI_ACTION_SELECT;
    /* the extra entries are the person's choice; the actions themselves stay available to a double tap */
    if (!NoshiChatFlagGet(NoshiChatFlagMenuCopyPhoto)) mask &= ~(uint32_t)NOSHI_ACTION_COPY_PHOTO;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuHistory)) mask &= ~(uint32_t)NOSHI_ACTION_HISTORY;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuReport)) mask &= ~(uint32_t)NOSHI_ACTION_REPORT;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuNoQuote)) mask &= ~(uint32_t)NOSHI_ACTION_FORWARD_HIDDEN;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuRemind)) mask &= ~(uint32_t)NOSHI_ACTION_REMIND;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuSave)) mask &= ~(uint32_t)NOSHI_ACTION_SAVE;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuRepeat)) mask &= ~(uint32_t)NOSHI_ACTION_REPEAT;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuDetails)) mask &= ~(uint32_t)NOSHI_ACTION_DETAILS;
    if (!NoshiChatFlagGet(NoshiChatFlagMenuBookmark)) mask &= ~(uint32_t)(NOSHI_ACTION_BOOKMARK | NOSHI_ACTION_UNBOOKMARK);
    if (!NoshiChatFlagGet(NoshiChatFlagMenuReplyPrivate)) mask &= ~(uint32_t)NOSHI_ACTION_REPLY_PRIVATE;
    /* the server refuses the list of who reacted in a broadcast channel (BROADCAST_FORBIDDEN, so that readers cannot be told apart), so the entry is not offered there */
    /* the post that heads its comments is that same post, forwarded into the discussion group, and the server refuses the list for it as well: it comes from a channel (its origin is one), or it is the root of the thread */
    else if (message.messageId > 0 && message.reactions.count && _dialog.kind != NOSHI_DIALOG_CHANNEL && _dialog.kind != NOSHI_DIALOG_USER && _dialog.kind != NOSHI_DIALOG_BOT &&
             !message.post && message.forwardKey >= 0 &&
             !(_dialog.topicId > 0 && message.messageId == _dialog.topicId)) mask |= NOSHI_ACTION_REACTORS;
    /* a one-time file must not be kept, sent on or sent again by this client */
    if (NoshiMessageIsViewOnce(message)) mask &= ~(uint32_t)(NOSHI_ACTION_FORWARD | NOSHI_ACTION_FORWARD_HIDDEN | NOSHI_ACTION_SAVE | NOSHI_ACTION_GALLERY |
                                                              NOSHI_ACTION_COPY_PHOTO | NOSHI_ACTION_REPEAT | NOSHI_ACTION_BOOKMARK | NOSHI_ACTION_UNBOOKMARK);
    if (!mask) return;
    [self dismissInput];
    NoshiWeakReference *weak = _weak;
    int32_t messageId = message.messageId;
    NoshiMessageMenu *menu = [[[NoshiMessageMenu alloc] init] autorelease];
    menu.media = _media;
    menu.icons = NoshiMenuItems(NoshiMessageActionIcons, sizeof(NoshiMessageActionIcons) / sizeof(NoshiMessageActionIcons[0]), mask);
    menu.rows = NoshiMenuItems(NoshiMessageActionRows, sizeof(NoshiMessageActionRows) / sizeof(NoshiMessageActionRows[0]), mask);
    menu.pickHandler = ^(NSUInteger tag) {
        NoshiChatController *chat = weak.target;
        /* the message may have gone while the menu was open */
        NoshiMessage *current = chat ? [chat storedMessageWithId:messageId] : nil;
        if (!current) return;
        [chat performAction:(noshi_message_action)tag onMessage:current];
    };
    menu.reactionHandler = ^(NoshiReaction *reaction) {
        NoshiChatController *chat = weak.target;
        if (chat && [chat messageWithId:messageId]) [chat chooseReaction:reaction messageId:messageId burst:NOSHI_BURST_NONE];
    };
    menu.moreReactionsHandler = ^{
        NoshiChatController *chat = weak.target;
        NoshiMessage *current = chat ? [chat messageWithId:messageId] : nil;
        if (!current) return;
        [chat showReactionPickerForMessage:current];
        if (chat->_reactionPicker) chat->_reactionPickerFromMenu = YES;
    };
    /* the pill: at once when the reactions are known, as they arrive otherwise */
    BOOL reactable = message.messageId > 0 && message.reactionsPossible && ![self reactionsHidden];
    if (reactable && _menuReactions) {
        [menu setReactions:[self menuReactionsForMessage:message]];
    } else if (reactable) {
        NoshiMessageMenu *shown = menu;
        [self loadMenuReactionsThen:^{
            NoshiChatController *chat = weak.target;
            NoshiMessage *current = chat ? [chat messageWithId:messageId] : nil;
            if (current) [shown setReactions:[chat menuReactionsForMessage:current]];
        }];
    }
    /* the line of the reactions stands under the one about reading, and its faces are the first people of the list the server gives */
    if (mask & NOSHI_ACTION_REACTORS) [self fillReactorsLineOfMenu:menu message:message];
    /* a message of ours in a private chat says whether it was read and when */
    if (message.outgoing && message.messageId > 0 && (_dialog.kind == NOSHI_DIALOG_USER || _dialog.kind == NOSHI_DIALOG_BOT) && !_dialog.saved) {
        BOOL read = message.messageId <= [self readOutboxMaxId];
        if (read) [menu setHeaderText:NSLocalizedString(@"chat.msg.read", nil) read:YES];
        else {
            [menu setHeaderText:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.sentat", nil), NoshiClockText(message.date)] read:NO];
        }
        NoshiMessageMenu *shown = menu;
        [_session loadReadDateOfMessageId:message.messageId ofDialog:_dialog completion:^(int32_t date, NSString *errorName) {
            if (errorName || date <= 0) {
                if (read) [shown setHeaderText:NSLocalizedString(@"chat.msg.readtime.unavailable", nil) read:YES];
                return;
            }
            [shown setHeaderText:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.readat", nil), NoshiMediaTimeText(date)] read:YES];
        }];
    } else if (message.outgoing && message.messageId > 0 && _dialog.kind == NOSHI_DIALOG_GROUP && !_dialog.saved) {
        NoshiMessageMenu *shown = menu;
        [menu setHeaderText:NSLocalizedString(@"chat.msg.readtime.loading", nil) read:NO];
        [_session loadGroupReadDatesOfMessageId:message.messageId ofDialog:_dialog completion:^(NSArray *readers, NSString *errorName) {
            if (errorName) [shown setHeaderText:NSLocalizedString(@"chat.msg.readtime.unavailable", nil) read:NO];
            else if (!readers.count) [shown setHeaderText:NSLocalizedString(@"chat.msg.unread", nil) read:NO];
            else {
                shown.headerHandler = ^{
                    NoshiChatController *chat = weak.target;
                    if (!chat) return;
                    NoshiSettingsPageController *page = [[[NoshiSettingsPageController alloc] init] autorelease];
                    page.pageTitle = NSLocalizedString(@"chat.msg.readers", nil);
                    [chat fillReadersPage:page readers:readers people:chat->_people];
                    [chat.navigationController pushViewController:page animated:YES];
                    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:readers.count];
                    for (NSDictionary *reader in readers) [ids addObject:[reader objectForKey:@"user"]];
                    [chat->_session loadCachedPeopleWithIds:ids completion:^(NSDictionary *people) {
                        NoshiChatController *again = weak.target;
                        if (!again) return;
                        for (NSNumber *key in people) {
                            NoshiPerson *known = [again->_people objectForKey:key], *cached = [people objectForKey:key];
                            if (!known || (!known.photo && cached.photo)) [again->_people setObject:cached forKey:key];
                        }
                        [again fillReadersPage:page readers:readers people:again->_people];
                    }];
                    if (chat->_dialog.peerKind == 2) {
                        [chat->_session loadSenderRolesOfDialog:chat->_dialog completion:^(NSDictionary *roles, NSDictionary *people, NSString *error) {
                            (void)roles;
                            NoshiChatController *again = weak.target;
                            if (!again) return;
                            if (error) { NSLog(@"noshigram: read participants could not be loaded: %@", error); return; }
                            [again->_people addEntriesFromDictionary:people];
                            [again fillReadersPage:page readers:readers people:again->_people];
                        }];
                    }
                    if (chat->_dialog.peerKind == 3) {
                        [chat->_session loadMembersOfDialog:chat->_dialog list:NoshiChannelListSubscribers query:nil offset:0 completion:^(NSArray *members, NSInteger total, NSString *error) {
                            (void)total;
                            NoshiChatController *again = weak.target;
                            if (!again) return;
                            if (error) { NSLog(@"noshigram: read participants' names could not be loaded: %@", error); return; }
                            for (NoshiChannelMember *member in members) {
                                if (member.person.userId > 0) [again->_people setObject:member.person forKey:[NSNumber numberWithLongLong:member.person.userId]];
                            }
                            [again fillReadersPage:page readers:readers people:again->_people];
                        }];
                    }
                };
                [shown setHeaderText:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.readers.count", nil), (unsigned long)readers.count] read:YES];
                /* the first three of them: whoever of them the chat does not know yet comes from what the store holds */
                NSMutableArray *firstIds = [NSMutableArray array];
                for (NSDictionary *reader in readers) { if (firstIds.count < 3) [firstIds addObject:[reader objectForKey:@"user"]]; }
                void (^showFaces)(void) = ^{
                    NoshiChatController *chat = weak.target;
                    if (!chat) return;
                    NSMutableArray *faces = [NSMutableArray array];
                    for (NSNumber *key in firstIds) { NoshiPerson *person = [chat->_people objectForKey:key]; if (person) [faces addObject:person]; }
                    [shown setHeaderPeople:faces cache:chat->_avatars];
                };
                showFaces();
                NoshiChatController *host = weak.target;
                if (host) [host->_session loadCachedPeopleWithIds:firstIds completion:^(NSDictionary *people) {
                    NoshiChatController *again = weak.target;
                    if (!again) return;
                    for (NSNumber *key in people) if (![again->_people objectForKey:key]) [again->_people setObject:[people objectForKey:key] forKey:key];
                    showFaces();
                }];
            }
        }];
    }
    CGRect bubble = [self.view convertRect:cell.item.bubbleFrame fromView:cell.contentView];
    CGRect rowFrame = [self.view convertRect:cell.contentView.bounds fromView:cell.contentView];
    CGRect clip = CGRectIntersection(rowFrame, _table.frame);
    if (CGRectIsNull(clip)) clip = CGRectZero;
    /* a message that is no taller than the list is lit whole, over the bar it was scrolled under, and the menu slides it into place; only a taller one
       (or half under the field) is lit and measured by the part of it that the list shows */
    BOOL fits = rowFrame.size.height <= _table.frame.size.height;
    CGRect litArea = _table.frame;
    if (fits) {
        litArea = self.view.bounds;
        CGRect whole = CGRectIntersection(bubble, self.view.bounds);
        if (!CGRectIsNull(whole) && !CGRectIsEmpty(whole)) bubble = whole;
    } else {
        CGRect shown = CGRectIntersection(bubble, _table.frame);
        if (!CGRectIsNull(shown) && !CGRectIsEmpty(shown)) bubble = shown;
    }
    [menu showInView:self.view bubble:bubble outgoing:message.outgoing snapshot:CGRectIsEmpty(clip) ? nil : [cell contentSnapshot] snapshotFrame:rowFrame clip:litArea];
}

- (BOOL)messageCellCanSwipeReply:(NoshiMessageCell *)cell {
    if (_pinnedList || _joinPending || !cell.item.message) return NO;
    noshi_action_context context = [self actionContextOfMessage:cell.item.message];
    return (noshi_message_actions_for(&context) & NOSHI_ACTION_REPLY) != 0;
}

- (void)messageCellDidSwipeReply:(NoshiMessageCell *)cell {
    NoshiMessage *message = [self messageWithId:cell.item.message.messageId];
    if (message) [self beginReplyToMessage:message];
}

- (NoshiMessage *)storedMessageWithId:(int32_t)messageId {
    NoshiMessage *message = [_server objectForKey:[NSNumber numberWithInt:messageId]];
    if (message) return message;
    for (NoshiMessage *local in _local) if (local.messageId == messageId) return local;
    return nil;
}

- (NoshiMessage *)messageWithId:(int32_t)messageId {
    NoshiMessage *message = [self storedMessageWithId:messageId];
    return message;
}

- (void)performAction:(noshi_message_action)action onMessage:(NoshiMessage *)message {
    switch (action) {
    case NOSHI_ACTION_REACT: [self showReactionPickerForMessage:message]; break;
    case NOSHI_ACTION_REPLY: [self beginReplyToMessage:message]; break;
    case NOSHI_ACTION_SELECT_TEXT: [self selectTextOfMessage:message]; break;
    case NOSHI_ACTION_COPY:
        [UIPasteboard generalPasteboard].string = message.text;
        [self toast:NSLocalizedString(@"profile.copied", nil)];
        break;
    case NOSHI_ACTION_COPY_LINK: [self copyLinkOfMessage:message]; break;
    case NOSHI_ACTION_REMIND: [self chooseReminderForMessage:message]; break;
    case NOSHI_ACTION_REPLY_PRIVATE: [self replyInPrivateToMessage:message]; break;
    case NOSHI_ACTION_EDIT: [self beginEditingMessage:message]; break;
    case NOSHI_ACTION_FORWARD: [self forwardMessage:message hideAuthor:NO]; break;
    case NOSHI_ACTION_FORWARD_HIDDEN: [self forwardMessage:message hideAuthor:YES]; break;
    case NOSHI_ACTION_COPY_PHOTO: [self copyPhotoOfMessage:message]; break;
    case NOSHI_ACTION_HISTORY: [self openHistoryOfMessage:message]; break;
    case NOSHI_ACTION_REPORT:
        [NoshiMessageReportFlow startForMessageIds:[NSArray arrayWithObject:[NSNumber numberWithInt:message.messageId]] dialog:_dialog session:_session host:self];
        break;
    case NOSHI_ACTION_SAVE: [self saveMessageToFavorites:message]; break;
    case NOSHI_ACTION_SAVE_MUSIC: [self addSongToProfile:message.media]; break;
    case NOSHI_ACTION_GALLERY: [self saveMediaOfMessage:message]; break;
    case NOSHI_ACTION_SELECT: [self beginSelectionWith:message]; break;
    case NOSHI_ACTION_BOOKMARK: [self bookmarkMessage:message]; break;
    case NOSHI_ACTION_UNBOOKMARK:
        if ([[NoshiBookmarks bookmarksForSession:_session] removeMessageId:message.messageId inDialog:_dialog]) [self toast:NSLocalizedString(@"chat.msg.unbookmarked", nil)];
        else NoshiGiftAlert(nil, NSLocalizedString(@"bookmarks.failed", nil));
        break;
    case NOSHI_ACTION_TRANSCRIBE: [self transcribeMessage:message]; break;
    case NOSHI_ACTION_TRANSLATE: [self translateMessage:message]; break;
    case NOSHI_ACTION_REPEAT: {
        NSString *again = [[message.text copy] autorelease];
        [self askFirst:NoshiChatFlagAskRepeat message:NSLocalizedString(@"chat.ask.repeat", nil) action:NSLocalizedString(@"chat.ask.repeat.action", nil) then:^{
            [self sendText:again entities:nil];
        } declined:nil];
        break;
    }
    case NOSHI_ACTION_PIN: [self pinMessage:message unpin:NO]; break;
    case NOSHI_ACTION_UNPIN: [self pinMessage:message unpin:YES]; break;
    case NOSHI_ACTION_DETAILS: [self showDetailsOfMessage:message]; break;
    case NOSHI_ACTION_STATISTICS: {
        NoshiMessageStatsController *page = [[[NoshiMessageStatsController alloc] initWithSession:_session dialog:_dialog message:message avatars:_avatars] autorelease];
        [self.navigationController pushViewController:page animated:YES];
        break;
    }
    case NOSHI_ACTION_DELETE:
        _deleteId = message.messageId;
        [self askWithMessage:NSLocalizedString(@"chat.msg.delete.confirm", nil) action:NSLocalizedString(@"chat.msg.delete", nil) tag:NoshiChatAlertDeleteMessage];
        break;
    }
}

#pragma mark reply and edit

- (void)showComposeSymbol:(NoshiSymbol)symbol title:(NSString *)title text:(NSString *)text {
    [_context showSymbol:symbol title:title text:text];
    _context.hidden = NO;
    [self relayoutAnimatedThen:nil];
}

- (void)beginReplyToMessage:(NoshiMessage *)message {
    [self showReplyToMessage:message];
    [_input.textView becomeFirstResponder];
}

/* the strip over the field names the message answered; a draft that answers one brings it back without the keyboard */
- (void)showReplyToMessage:(NoshiMessage *)message {
    [self cancelCompose];
    _pendingDraftReply = 0;
    _replyToId = message.messageId;
    [self showComposeSymbol:NoshiSymbolReply title:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.reply.title", nil), [self senderNameOfMessage:message]]
                       text:NoshiMessageSummary(message)];
    [self draftStateChanged];
}

/* the words are selected in the bubble itself; one selection stands at a time */
- (void)selectTextOfMessage:(NoshiMessage *)message {
    [self clearTextSelection];
    for (NoshiMessageCell *cell in [_table visibleCells]) {
        if (![cell isKindOfClass:[NoshiMessageCell class]] || !cell.item.message || cell.item.message.messageId != message.messageId) continue;
        [cell beginTextSelection];
        return;
    }
}

- (void)clearTextSelection {
    for (NoshiMessageCell *cell in [_table visibleCells]) if ([cell isKindOfClass:[NoshiMessageCell class]] && [cell hasTextSelection]) [cell clearTextSelection];
}

- (void)messageCell:(NoshiMessageCell *)cell didQuoteText:(NSString *)quote offset:(int32_t)offset {
    NoshiMessage *target = [self messageWithId:cell.item.message.messageId];
    if (!target || !quote.length) return;
    [self showReplyToMessage:target];
    [_replyQuote release];
    _replyQuote = [quote copy];
    _replyQuoteOffset = offset;
    [self showComposeSymbol:NoshiSymbolReply title:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.reply.title", nil), [self senderNameOfMessage:target]] text:quote];
    [_input.textView becomeFirstResponder];
}

- (void)beginEditingMessage:(NoshiMessage *)message {
    /* the words in the field are a draft, and editing another message must not turn them into that message's draft: they wait to come back */
    BOOL wasEditing = _editingId != 0;
    NoshiDraft *keep = wasEditing ? nil : [self fieldDraft];
    [self cancelCompose];
    if (wasEditing) keep = [self fieldDraft];
    [_stashedDraft release];
    _stashedDraft = [keep retain];
    _editingId = message.messageId;
    [self showComposeSymbol:NoshiSymbolCompose title:NSLocalizedString(@"chat.msg.edit.title", nil) text:message.text];
    [self applyDraft:message.text];
}

/* drops the strip; a message that was being edited takes its text out of the field with it */
- (void)cancelCompose {
    [self cancelComposeAnimated:YES];
}

/* a sent message closes the reply bar and adds its row in the same moment: with the bar sliding away the table changes height under the row that is being inserted and
   scrolled to, and the list went blank for a few frames, so that send closes the bar at once */
- (void)cancelComposeAnimated:(BOOL)animated {
    BOOL editing = _editingId != 0;
    _replyToId = 0;
    [_replyQuote release]; _replyQuote = nil;
    _pendingDraftReply = 0;
    _editingId = 0;
    if (_context.hidden) {
        [self draftStateChanged];
        return;
    }
    _context.hidden = YES;
    if (editing) {
        NoshiDraft *back = [[_stashedDraft retain] autorelease];
        [_stashedDraft release];
        _stashedDraft = nil;
        _applyingDraft = YES;
        if (back.text.length) [_input setText:back.text entities:back.entities];
        else [_input clear];
        _applyingDraft = NO;
        if (back.replyTo) [self restoreDraftReplyTo:back.replyTo];
    }
    if (animated) [self relayoutAnimatedThen:nil];
    else [self layoutChat];
    [self draftStateChanged];
}

#pragma mark drafts

/* the field and the strip as a draft would keep them */
- (NoshiDraft *)fieldDraft {
    NSString *text = [_input trimmedText];
    return [[[NoshiDraft alloc] initWithText:text entities:text.length ? [_input sendEntities] : nil replyTo:_replyToId ? _replyToId : _pendingDraftReply
                                     noWebpage:NoshiChatFlagGet(NoshiChatFlagNoLinkPreview) date:0] autorelease];
}

/* what two lists of entities say about the text, offsets and targets included */
static NSString *NoshiEntitySignature(NSArray *entities) {
    NSMutableString *signature = [NSMutableString string];
    for (NoshiTextEntity *entity in entities) {
        [signature appendFormat:@"%d:%lu:%lu:%@:%lld:%lld;", (int)entity.style, (unsigned long)entity.range.location, (unsigned long)entity.range.length,
                                entity.url ? entity.url : @"", entity.documentId, entity.userId];
    }
    return signature;
}

- (void)restoreDraft {
    if (_pinnedList || _dialog.savedSource) return;
    NoshiDraft *draft = [_session.drafts draftForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId];
    [self applyBoardDraft:draft];
}

/* puts a draft of the account in the field and the strip, without the keyboard and without taking it for something the person typed */
- (void)applyBoardDraft:(NoshiDraft *)draft {
    _applyingDraft = YES;
    if (draft.text.length) [_input setText:draft.text entities:draft.entities];
    else [_input clear];
    [self cancelCompose];
    _applyingDraft = NO;
    if (draft.replyTo) [self restoreDraftReplyTo:draft.replyTo];
}

- (void)restoreDraftReplyTo:(int32_t)messageId {
    NoshiMessage *known = [self messageWithId:messageId];
    if (known) {
        [self showReplyToMessage:known];
        return;
    }
    _pendingDraftReply = messageId;
    NoshiWeakReference *weak = _weak;
    [_session loadMessagesWithIds:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] ofDialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat || chat->_pendingDraftReply != messageId) return;
        chat->_pendingDraftReply = 0;
        NoshiMessage *found = messages.count ? [messages objectAtIndex:0] : nil;
        if (!found) {
            /* the message is gone, so the draft no longer answers anything and the next save says so */
            NSLog(@"noshigram: the message %d a draft answers did not load: %@", (int)messageId, errorName ? errorName : @"missing");
            [chat draftStateChanged];
            return;
        }
        if (chat->_replyToId || chat->_editingId) return;
        [chat showReplyToMessage:found];
    }];
}

- (void)draftStateChanged {
    if (!_draftsActive || _applyingDraft || _editingId) return;
    /* a save for every key press would be a request for every key press */
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraftNow) object:nil];
    [self performSelector:@selector(saveDraftNow) withObject:nil afterDelay:1.0];
}

- (void)saveDraftNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraftNow) object:nil];
    if (!_draftsActive || _applyingDraft || _editingId) return;
    NoshiDraft *field = [self fieldDraft];
    NoshiDraft *kept = [_session.drafts draftForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId];
    BOOL failed = [_session.drafts saveFailedForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId];
    if (!failed && field.empty && !kept) return;
    if (!failed && kept && [kept.text isEqualToString:field.text] && kept.replyTo == field.replyTo && kept.noWebpage == field.noWebpage &&
        [NoshiEntitySignature(kept.entities) isEqualToString:NoshiEntitySignature(field.entities)]) return;
    [_session saveDraftText:field.text entities:field.entities replyTo:field.replyTo noWebpage:field.noWebpage forDialog:_dialog];
}

/* the account sent another draft for this chat, such as one typed on another phone */
- (void)draftBoardChanged:(NSNotification *)note {
    if (!_draftsActive || _editingId || [[note.userInfo objectForKey:@"local"] boolValue] || !NoshiDraftChangeConcerns(note, _dialog)) return;
    /* what the person is typing here is not replaced under their fingers */
    if (_input.textView.isFirstResponder && [_input trimmedText].length) return;
    [self applyBoardDraft:[_session.drafts draftForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId]];
}

- (void)commitEditWithText:(NSString *)text {
    if (_editBusy) return;
    int32_t messageId = _editingId;
    NoshiMessage *original = [self messageWithId:messageId];
    if (!original || [original.text isEqualToString:text]) {
        [self cancelCompose];
        return;
    }
    _editBusy = YES;
    NoshiWeakReference *weak = _weak;
    /* a message with a picture, a video or a file changes its caption, and the media stays */
    noshi_preview_kind kind = original.media.kind;
    BOOL caption = kind != NOSHI_PREVIEW_NONE && kind != NOSHI_PREVIEW_TEXT;
    void (^edited)(NSString *) = ^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_editBusy = NO;
        /* the server saying nothing changed is the text it already has */
        if (errorName && ![errorName isEqualToString:@"MESSAGE_NOT_MODIFIED"]) {
            NSLog(@"noshigram: editing message %d failed: %@", (int)messageId, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        if (!errorName) {
            /* the server's copy comes back through the store, and reads the same; until it does the row says edited with the new words */
            NoshiMessage *shown = [chat messageWithId:messageId];
            [shown noteEditedToText:text];
            for (NoshiMessage *local in chat->_local) if (local.messageId == messageId) [local noteEditedToText:text];
            [chat rebuildItems];
        }
        if (chat->_editingId == messageId) [chat cancelCompose];
    };
    if (caption) [_session editCaptionOfMessageId:messageId ofDialog:_dialog text:text completion:edited];
    else [_session editMessageId:messageId ofDialog:_dialog text:text completion:edited];
}

#pragma mark pin, forward, delete, details

- (void)pinMessage:(NoshiMessage *)message unpin:(BOOL)unpin {
    NoshiWeakReference *weak = _weak;
    [_session pinMessageId:message.messageId ofDialog:_dialog unpin:unpin completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: pin of message %d failed: %@", (int)message.messageId, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [chat toast:NSLocalizedString(unpin ? @"chat.msg.unpinned" : @"chat.msg.pinned", nil)];
        /* the pinned bar of a channel follows the full channel */
        if (chat->_dialog.peerKind == 3) [chat loadChannelFull];
    }];
}

- (void)forwardMessages:(NSArray *)messages toDialog:(NoshiDialog *)target hideAuthor:(BOOL)hideAuthor completion:(void (^)(NSString *))completion {
    NoshiForwardMessages(_session, _media, _dialog, _dialog.noForwards || _channelFull.dialog.noForwards, messages, target, hideAuthor, completion);
}

- (void)forwardMessage:(NoshiMessage *)message hideAuthor:(BOOL)hideAuthor {
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"chat.msg.forward.to", nil);
    picker.forwarding = YES;
    picker.filter = ^BOOL(NoshiDialog *dialog) {
        return !dialog.folder && !dialog.community && (dialog.kind != NOSHI_DIALOG_CHANNEL || dialog.canPost);
    };
    NoshiWeakReference *weak = _weak;
    NSNumber *messageId = [NSNumber numberWithInt:message.messageId];
    picker.pickHandler = ^(NSArray *dialogs) {
        NoshiChatController *chat = weak.target;
        NoshiDialog *target = [dialogs lastObject];
        if (!chat || !target) return;
        [chat forwardMessages:[NSArray arrayWithObject:message] toDialog:target hideAuthor:hideAuthor completion:^(NSString *errorName) {
            NoshiChatController *again = weak.target;
            if (errorName) {
                NSLog(@"noshigram: forward of message %@ failed: %@", messageId, errorName);
                NoshiGiftAlert(nil, errorName);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
            [again toast:NSLocalizedString(@"chat.msg.forwarded", nil)];
        }];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

/* the address of a message: from the name of a public channel, or from the server for a private one */
- (void)copyLinkOfMessage:(NoshiMessage *)message {
    if (_channelFull.username.length) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://t.me/%@/%d", _channelFull.username, (int)message.messageId];
        [self toast:NSLocalizedString(@"chat.link.copied", nil)];
        return;
    }
    NoshiWeakReference *weak = _weak;
    [_session exportLinkOfMessageId:message.messageId ofDialog:_dialog completion:^(NSString *link, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!link) {
            NSLog(@"noshigram: the link of a message was not made: %@", errorName);
            NoshiGiftAlert(NSLocalizedString(@"chat.link.failed", nil), NoshiGiftErrorText(errorName));
            return;
        }
        [UIPasteboard generalPasteboard].string = link;
        [chat toast:NSLocalizedString(@"chat.link.copied", nil)];
    }];
}

/* a reminder is a message the server sends to the favorites later: the person picks the time from a few, and the text names the message */
- (void)chooseReminderForMessage:(NoshiMessage *)message {
    NSString *summary = NoshiMessageSummary(message);
    if (summary.length > 200) summary = [[summary substringToIndex:200] stringByAppendingString:@"\u2026"];
    NSString *line = [NSString stringWithFormat:NSLocalizedString(@"chat.remind.text", nil), summary];
    if (_channelFull.username.length) line = [NSString stringWithFormat:@"%@\nhttps://t.me/%@/%d", line, _channelFull.username, (int)message.messageId];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"chat.remind.hour", nil), NSLocalizedString(@"chat.remind.three", nil),
                       NSLocalizedString(@"chat.remind.tomorrow", nil), NSLocalizedString(@"chat.remind.week", nil), nil];
    NoshiWeakReference *weak = _weak;
    [NoshiSheet presentInView:self.view title:NSLocalizedString(@"chat.remind.title", nil) message:nil options:titles destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        NoshiChatController *chat = weak.target;
        if (chat) [chat scheduleReminder:line choice:index];
    }];
}

/* the times the sheets offer: an hour, three hours, the next 9:00 and a week from now */
static NSDate *NoshiReminderDate(NSUInteger choice) {
    NSDate *now = [NSDate date], *when = nil;
    switch (choice) {
    case 0: when = [now dateByAddingTimeInterval:3600]; break;
    case 1: when = [now dateByAddingTimeInterval:3 * 3600]; break;
    case 2: {
        /* the next 9:00 in the person's calendar, tomorrow's even when it is not yet 9:00 today */
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents *parts = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[now dateByAddingTimeInterval:86400]];
        parts.hour = 9;
        when = [calendar dateFromComponents:parts];
        break;
    }
    default: when = [now dateByAddingTimeInterval:7 * 86400]; break;
    }
    return when;
}

- (void)scheduleReminder:(NSString *)line choice:(NSUInteger)choice {
    NSDate *when = NoshiReminderDate(choice);
    if (!when) return;
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        NoshiPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (!chat) return;
        if (!me) {
            NSLog(@"noshigram: the account is not known for a reminder: %@", errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [chat->_session scheduleText:line atDate:(int32_t)[when timeIntervalSince1970] toDialog:[NoshiDialog savedMessagesOfUserId:me.userId]
                          completion:^(NSString *scheduleError) {
            NoshiChatController *again = weak.target;
            if (!again) return;
            if (scheduleError) {
                NSLog(@"noshigram: the reminder was not set: %@", scheduleError);
                NoshiGiftAlert(nil, NoshiGiftErrorText(scheduleError));
                return;
            }
            [again toast:NSLocalizedString(@"chat.remind.set", nil)];
        }];
    }];
}

/* the private chat with the sender of a group message, with the words of the message quoted in the field */
- (void)replyInPrivateToMessage:(NoshiMessage *)message {
    NoshiPerson *sender = [_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    NoshiDialog *dialog = sender ? [NoshiDialog dialogWithPerson:sender] : nil;
    if (!dialog) {
        [self toast:NSLocalizedString(@"error.internal", nil)];
        return;
    }
    NSString *summary = NoshiMessageSummary(message);
    if (summary.length > 120) summary = [[summary substringToIndex:120] stringByAppendingString:@"\u2026"];
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.draftText = [NSString stringWithFormat:@"\u00ab%@\u00bb\n", summary];
    [self.navigationController pushViewController:chat animated:YES];
}

/* the picture of a photo goes to the pasteboard */
- (void)copyPhotoOfMessage:(NoshiMessage *)message {
    NoshiWeakReference *weak = _weak;
    [NoshiGallerySaver copyPhotoOfMedia:message.media cache:_media completion:^(NSString *failureKey) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (failureKey) NoshiGiftAlert(nil, NSLocalizedString(failureKey, nil));
        else [chat toast:NSLocalizedString(@"profile.copied", nil)];
    }];
}

/* everything the sender wrote in this group, as a list over the chat like the search results */
- (void)openHistoryOfMessage:(NoshiMessage *)message {
    NoshiPerson *sender = [_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    if (!sender) return;
    NoshiChatController *list = [[[NoshiChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    list.pinnedList = YES;
    list.historyPerson = sender;
    [self.navigationController pushViewController:list animated:YES];
}

/* the photo or video goes to the library of the phone; a large video takes a while, so the person is told it started */
- (void)saveMediaOfMessage:(NoshiMessage *)message {
    [self toast:NSLocalizedString(@"chat.msg.gallery.saving", nil)];
    NoshiWeakReference *weak = _weak;
    [NoshiGallerySaver saveMedia:message.media cache:_media completion:^(NSString *failureKey) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (failureKey) NoshiGiftAlert(nil, NSLocalizedString(failureKey, nil));
        else [chat toast:NSLocalizedString(@"media.saved", nil)];
    }];
}

#pragma mark selection

/* the messages that are picked, oldest first, and only those the screen still holds */
- (NSArray *)selectedMessages {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSNumber *identifier in _selectedIds) {
        NoshiMessage *message = [self messageWithId:identifier.intValue];
        if (message) [messages addObject:message];
    }
    [messages sortUsingComparator:^NSComparisonResult(NoshiMessage *a, NoshiMessage *b) {
        return a.messageId < b.messageId ? NSOrderedAscending : (a.messageId > b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
    return messages;
}

/* the bar says how many are picked and offers what all of them allow together */
- (void)refreshSelectionBar {
    NSArray *messages = [self selectedMessages];
    uint32_t masks[NOSHI_MESSAGES_MAX];
    size_t count = MIN(messages.count, (NSUInteger)NOSHI_MESSAGES_MAX);
    for (size_t i = 0; i < count; ++i) {
        noshi_action_context context = [self actionContextOfMessage:[messages objectAtIndex:i]];
        masks[i] = noshi_message_actions_for(&context);
    }
    uint32_t together = noshi_selection_actions(masks, count);
    [_selectionBar setCount:messages.count forward:(together & NOSHI_ACTION_FORWARD) != 0 copy:(together & NOSHI_ACTION_COPY) != 0
                     delete:(together & NOSHI_ACTION_DELETE) != 0 range:messages.count >= 2];
}

/* every message of the screen between the oldest and the newest of those picked joins them, as far as one request can carry */
- (void)selectBetween {
    if (_selectedIds.count < 2) return;
    NSInteger first = NSNotFound, last = NSNotFound;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        NoshiChatItem *item = [_items objectAtIndex:i];
        if (!item.message || item.kind == NoshiChatItemPill || ![_selectedIds containsObject:[NSNumber numberWithInt:item.message.messageId]]) continue;
        if (first == NSNotFound) first = (NSInteger)i;
        last = (NSInteger)i;
    }
    if (first == NSNotFound || last <= first) return;
    for (NSInteger i = first; i <= last && _selectedIds.count < NOSHI_MESSAGES_MAX; ++i) {
        NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)i];
        if (item.message && item.kind != NoshiChatItemPill && item.message.messageId > 0) [_selectedIds addObject:[NSNumber numberWithInt:item.message.messageId]];
    }
    [self refreshSelectionBar];
    [self refreshSelectionOnCells];
}

- (void)refreshSelectionOnCells {
    for (UITableViewCell *row in _table.visibleCells) {
        NoshiMessageCell *cell = (NoshiMessageCell *)row;
        if (![cell isKindOfClass:[NoshiMessageCell class]]) continue;
        [cell setSelecting:_selecting selected:[_selectedIds containsObject:[NSNumber numberWithInt:cell.item.message.messageId]] animated:YES];
    }
}

- (void)beginSelectionWith:(NoshiMessage *)message {
    [self cancelCompose];
    [self dismissInput];
    _selecting = YES;
    [_selectedIds release];
    _selectedIds = [[NSMutableSet alloc] initWithObjects:[NSNumber numberWithInt:message.messageId], nil];
    _inputHiddenBeforeSelection = _input.hidden;
    _input.hidden = YES;
    _selectionBar.hidden = NO;
    [self refreshSelectionBar];
    [self refreshSelectionOnCells];
    [self relayoutAnimatedThen:nil];
}

- (void)endSelection {
    if (!_selecting) return;
    _selecting = NO;
    [_selectedIds removeAllObjects];
    _selectionBar.hidden = YES;
    _input.hidden = _inputHiddenBeforeSelection;
    [self refreshSelectionOnCells];
    [self relayoutAnimatedThen:nil];
}

- (void)messageCellDidToggleSelection:(NoshiMessageCell *)cell {
    NSNumber *identifier = [NSNumber numberWithInt:cell.item.message.messageId];
    if ([_selectedIds containsObject:identifier]) {
        [_selectedIds removeObject:identifier];
    } else if (_selectedIds.count >= NOSHI_MESSAGES_MAX) {
        /* one request carries this many, which is as many as can be forwarded or deleted together */
        [self toast:NSLocalizedString(@"chat.select.limit", nil)];
        return;
    } else {
        [_selectedIds addObject:identifier];
    }
    [cell setSelecting:YES selected:[_selectedIds containsObject:identifier] animated:YES];
    [self refreshSelectionBar];
}

- (void)copySelected {
    NSMutableArray *texts = [NSMutableArray array];
    for (NoshiMessage *message in [self selectedMessages]) if (message.text.length) [texts addObject:message.text];
    if (!texts.count) return;
    [UIPasteboard generalPasteboard].string = [texts componentsJoinedByString:@"\n"];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
    [self endSelection];
}

- (void)forwardSelected {
    NSArray *messages = [self selectedMessages];
    NSMutableArray *ids = [NSMutableArray array];
    for (NoshiMessage *message in messages) [ids addObject:[NSNumber numberWithInt:message.messageId]];
    if (!ids.count) return;
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"chat.msg.forward.to", nil);
    picker.forwarding = YES;
    picker.filter = ^BOOL(NoshiDialog *dialog) {
        return !dialog.folder && !dialog.community && (dialog.kind != NOSHI_DIALOG_CHANNEL || dialog.canPost);
    };
    NoshiWeakReference *weak = _weak;
    picker.pickHandler = ^(NSArray *dialogs) {
        NoshiChatController *chat = weak.target;
        NoshiDialog *target = [dialogs lastObject];
        if (!chat || !target) return;
        [chat forwardMessages:messages toDialog:target hideAuthor:NO completion:^(NSString *errorName) {
            NoshiChatController *again = weak.target;
            if (errorName) {
                NSLog(@"noshigram: forward of %lu messages failed: %@", (unsigned long)ids.count, errorName);
                NoshiGiftAlert(nil, errorName);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
            [again toast:NSLocalizedString(@"chat.msg.forwarded", nil)];
            [again endSelection];
        }];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)askDeleteSelected {
    if (![self selectedMessages].count) return;
    [self askWithMessage:[NSString stringWithFormat:NSLocalizedString(@"chat.select.delete.confirm", nil), (long)[self selectedMessages].count]
                  action:NSLocalizedString(@"chat.msg.delete", nil) tag:NoshiChatAlertDeleteSelected];
}

- (void)deleteSelectedNow {
    NSMutableArray *ids = [NSMutableArray array];
    for (NoshiMessage *message in [self selectedMessages]) [ids addObject:[NSNumber numberWithInt:message.messageId]];
    if (!ids.count) return;
    NoshiWeakReference *weak = _weak;
    [_session deleteMessageIds:ids ofDialog:_dialog revoke:!NoshiChatFlagGet(NoshiChatFlagDeleteForMe) completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: delete of %lu messages failed: %@", (unsigned long)ids.count, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        for (NSNumber *identifier in ids) {
            [chat->_server removeObjectForKey:identifier];
            for (NoshiMessage *local in [[chat->_local copy] autorelease]) if (local.messageId == identifier.intValue) [chat->_local removeObject:local];
            if (chat->_replyToId == identifier.intValue || chat->_editingId == identifier.intValue) [chat cancelCompose];
        }
        [chat endSelection];
        [chat rebuildItems];
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
    }];
}

/* the message goes into the list of bookmarks of this phone, with a line to know it by */
- (void)bookmarkMessage:(NoshiMessage *)message {
    if ([[NoshiBookmarks bookmarksForSession:_session] addMessageId:message.messageId date:message.date text:NoshiMessageSummary(message) inDialog:_dialog]) {
        [self toast:NSLocalizedString(@"chat.msg.bookmarked", nil)];
    } else {
        NoshiGiftAlert(nil, NSLocalizedString(@"bookmarks.failed", nil));
    }
}

#pragma mark transcript

/* the server writes a voice message down; it may still be listening, so a pending answer is asked for again a moment later */
#pragma mark translation

/* the button is off until the settings turn it on, and a message in a language the person left alone has none; a text whose language cannot be told has it */
- (BOOL)translateWantedForMessage:(NoshiMessage *)message {
    if (!NoshiTranslateButtonEnabled() || !message.text.length) return NO;
    NSString *guess = NoshiGuessLanguageOfText(message.text);
    return !(guess && NoshiTranslateSkips(guess));
}

/* the lines before the message, for an AI translator that was asked to read them */
- (NSString *)translationContextBefore:(NoshiMessage *)message {
    if (NoshiTranslateProviderChoice() != NoshiTranslateProviderLLM || !NoshiLlmUsesContext()) return nil;
    NSMutableArray *before = [NSMutableArray array];
    for (NoshiMessage *other in [_server allValues]) {
        if (other.messageId > 0 && other.messageId < message.messageId && other.text.length && !other.service) [before addObject:other];
    }
    [before sortUsingComparator:^NSComparisonResult(NoshiMessage *a, NoshiMessage *b) {
        return a.messageId > b.messageId ? NSOrderedAscending : (a.messageId < b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger count = MIN(before.count, (NSUInteger)NoshiLlmContextCount());
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger i = count; i > 0; --i) {
        NoshiMessage *other = [before objectAtIndex:i - 1];
        [lines addObject:[NSString stringWithFormat:@"%@: %@", [self senderNameOfMessage:other], other.text]];
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}

- (void)translateMessage:(NoshiMessage *)message {
    if (!message.text.length) return;
    NSString *context = [self translationContextBefore:message];
    /* a toast while the service works, then the words with Copy in the system alert */
    [self toast:NSLocalizedString(@"tr.translating", nil)];
    [NoshiTranslateJob translateText:message.text entities:message.entities to:NoshiTranslateTargetLanguage() context:context session:_session
                             completion:^(NoshiTranslation *translation, NSString *failure) {
        if (!translation) {
            NoshiShowNotice(NSLocalizedString(@"tr.sheet.title", nil), failure);
            return;
        }
        NSString *words = translation.text;
        NoshiShowAlert(NSLocalizedString(@"tr.sheet.title", nil), words, [NSArray arrayWithObjects:NSLocalizedString(@"tr.sheet.close", nil), NSLocalizedString(@"tr.copy", nil), nil], 0, NO,
                         ^(NSInteger index, NSString *text) {
            (void)text;
            if (index == 1) [UIPasteboard generalPasteboard].string = words;
        });
    }];
}

- (void)transcribeMessage:(NoshiMessage *)message {
    if (!_transcripts) _transcripts = [[NSMutableDictionary alloc] init];
    [self toast:NSLocalizedString(@"chat.msg.transcribing", nil)];
    [self requestTranscriptOfMessageId:message.messageId attempt:0];
}

- (void)requestTranscriptOfMessageId:(int32_t)messageId attempt:(NSUInteger)attempt {
    NoshiWeakReference *weak = _weak;
    [_session transcribeMessageId:messageId ofDialog:_dialog completion:^(NSString *text, BOOL pending, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: transcription of message %d failed: %@", (int)messageId, errorName);
            /* an account without Premium that has an AI provider set for the translator has its voice notes written by that provider */
            if ([errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] && [chat transcribeWithProviderMessageId:messageId]) return;
            NoshiGiftAlert(nil, [errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] ? NSLocalizedString(@"chat.msg.transcribe.premium", nil)
                                                                                      : NoshiGiftErrorText(errorName));
            return;
        }
        if (text.length) [chat showTranscript:text ofMessageId:messageId];
        if (pending && attempt < 12) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [(NoshiChatController *)weak.target requestTranscriptOfMessageId:messageId attempt:attempt + 1];
            });
        } else if (!text.length) {
            NoshiGiftAlert(nil, NSLocalizedString(@"chat.msg.transcribe.empty", nil));
        }
    }];
}

- (BOOL)transcribeWithProviderMessageId:(int32_t)messageId {
    NoshiMessage *message = [self messageWithId:messageId];
    if (!message || message.media.kind != NOSHI_PREVIEW_VOICE || !message.media.file || ![NoshiVoiceTranscriber isConfigured]) return NO;
    [self toast:NSLocalizedString(@"chat.msg.transcribe.ai", nil)];
    NoshiWeakReference *weak = _weak;
    [_voiceJob cancel];
    [_voiceJob release];
    _voiceJob = nil;
    [_media loadPathForFile:message.media.file size:message.media.size progress:nil completion:^(NSString *path) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!path) {
            NoshiGiftAlert(nil, NSLocalizedString(@"chat.msg.transcribe.unreadable", nil));
            return;
        }
        chat->_voiceJob = [[NoshiVoiceTranscriber transcribeVoiceAtPath:path completion:^(NSString *text, NSString *failure) {
            NoshiChatController *owner = weak.target;
            if (!owner) return;
            if (failure) {
                NoshiGiftAlert(nil, failure);
                return;
            }
            if (text.length) [owner showTranscript:text ofMessageId:messageId];
            else NoshiGiftAlert(nil, NSLocalizedString(@"chat.msg.transcribe.empty", nil));
        }] retain];
    }];
    return YES;
}

/* the words go under the voice message; its item is built again to carry them */
- (void)showTranscript:(NSString *)text ofMessageId:(int32_t)messageId {
    NoshiMessage *message = [self messageWithId:messageId];
    if (!message) return;
    [_transcripts setObject:text forKey:[NSNumber numberWithInt:messageId]];
    [_itemCache removeObjectForKey:[self cacheKeyForMessage:message]];
    [self rebuildItems];
}

/* one tap passes the message to the favorites, with no list of chats to pick from; the favorites are the chat with the account's own user id */
- (void)saveMessageToFavorites:(NoshiMessage *)message {
    NoshiWeakReference *weak = _weak;
    NSNumber *messageId = [NSNumber numberWithInt:message.messageId];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        NoshiPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (!chat) return;
        if (!me) {
            NSLog(@"noshigram: the account is not known for the favorites: %@", errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [chat forwardMessages:[NSArray arrayWithObject:message] toDialog:[NoshiDialog savedMessagesOfUserId:me.userId] hideAuthor:NO
                   completion:^(NSString *forwardError) {
            NoshiChatController *again = weak.target;
            if (!again) return;
            if (forwardError) {
                NSLog(@"noshigram: saving message %@ failed: %@", messageId, forwardError);
                NoshiGiftAlert(nil, forwardError);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
            [again toast:NSLocalizedString(@"chat.msg.saved", nil)];
        }];
    }];
}

- (void)deleteMessageNow {
    int32_t messageId = _deleteId;
    _deleteId = 0;
    if (messageId <= 0) return;
    NoshiWeakReference *weak = _weak;
    NoshiMessage *message = [self storedMessageWithId:messageId];
    if (!message) return;
    void (^finished)(NSString *) = ^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: delete of message %d failed: %@", (int)messageId, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [chat->_server removeObjectForKey:[NSNumber numberWithInt:messageId]];
        for (NoshiMessage *local in [[chat->_local copy] autorelease]) if (local.messageId == messageId) [chat->_local removeObject:local];
        if (chat->_replyToId == messageId || chat->_editingId == messageId) [chat cancelCompose];
        [chat rebuildItems];
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
    };
    [_session deleteMessageIds:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] ofDialog:_dialog revoke:!NoshiChatFlagGet(NoshiChatFlagDeleteForMe) completion:finished];
}

- (void)showDetailsOfMessage:(NoshiMessage *)message {
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.id", nil), (int)message.messageId]];
    NSDate *sent = [NSDate dateWithTimeIntervalSince1970:message.date];
    [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.sent", nil),
        [NSDateFormatter localizedStringFromDate:sent dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]]];
    if (!message.post) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.from", nil), [self senderNameOfMessage:message]]];
    if (message.forwarded) {
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.forward", nil),
            NoshiForwardName(message, _people).length ? NoshiForwardName(message, _people) : NSLocalizedString(@"chat.someone", nil)]];
    }
    if (message.views > 0) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.views", nil), (int)message.views]];
    if (message.media.kind == NOSHI_PREVIEW_VOICE) {
        /* of a note that came in, the time the phone heard it; of one of ours, only whether the other side did, since the server gives no time */
        if (message.listenedDate) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.listened", nil),
            [NSDateFormatter localizedStringFromDate:message.listenedDate dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]]];
        else [lines addObject:NSLocalizedString(message.mediaUnread ? @"chat.msg.details.notlistened" : @"chat.msg.details.listenedunknown", nil)];
    }
    NoshiGiftAlert(NSLocalizedString(@"chat.msg.details", nil), [lines componentsJoinedByString:@"\n"]);
}

#pragma mark gifts

/* a gift goes to a person: not to a bot, a group, a channel or the chat with oneself */
- (BOOL)canReceiveGift {
    return _dialog.kind == NOSHI_DIALOG_USER && !_dialog.saved;
}

- (void)openGiftCatalog {
    NoshiGiftCatalogController *catalog = [[[NoshiGiftCatalogController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:catalog animated:YES];
}

/* the picture and name at the top of the chat open the gifts of that person, or our own for the saved messages */
/* the favorites split by the chat each message came from, as the saved chats of exteraGram */
- (void)openSavedDialogs {
    [self.navigationController pushViewController:NoshiTopicsScreen(_session, _dialog, _avatars, _media, _stickers, nil) animated:YES];
}

- (void)openProfileGifts {
    NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
    BOOL channelLike = _dialog.peerKind == 3;
    if (!_dialog.saved && _dialog.kind != NOSHI_DIALOG_USER && _dialog.kind != NOSHI_DIALOG_BOT && !channelLike) return;
    [_input.textView resignFirstResponder];
    UIViewController *screen;
    if (_dialog.saved) {
        screen = [[[NoshiSavedMediaController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media] autorelease];
    } else if (channelLike) {
        screen = [[[NoshiChannelProfileController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    } else {
        screen = [[[NoshiUserProfileController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    }
    [self.navigationController pushViewController:screen animated:YES];
    NSLog(@"noshigram: the profile screen was made and pushed in %.0f ms", ([NSDate timeIntervalSinceReferenceDate] - began) * 1000);
}

/* the chat as a sender: what an anonymous admin's message shows as its name and picture */
- (NoshiPerson *)chatAsPerson {
    noshi_person_row row;
    memset(&row, 0, sizeof(row));
    row.id = _dialog.peerId;
    row.access_hash = _dialog.peerHash;
    snprintf(row.name, sizeof(row.name), "%s", _dialog.title.UTF8String);
    if (_dialog.photo) row.photo = _dialog.photo.ref;
    return [[[NoshiPerson alloc] initWithRow:&row] autorelease];
}

- (void)messageCellDidTapSender:(NoshiMessageCell *)cell {
    [self openSender:cell.item.senderPerson key:cell.item.message.senderKey messageId:cell.item.message.messageId];
}

/* the line of a service message opens the profile of the person it is about: the one added, removed or invited, and for the rest (a join, a new title, a pin) whoever did it */
- (void)messageCellDidTapService:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    switch ((noshi_service_kind)(message.service - 1)) {
    case NOSHI_SERVICE_OTHER:
    case NOSHI_SERVICE_CALL:
    case NOSHI_SERVICE_HISTORY_CLEAR:
    case NOSHI_SERVICE_MIGRATED:
    case NOSHI_SERVICE_CUSTOM:
        return;
    default:
        break;
    }
    BOOL aboutTarget = message.service == NOSHI_SERVICE_USER_ADDED + 1 || message.service == NOSHI_SERVICE_USER_REMOVED + 1 ||
                       message.service == NOSHI_SERVICE_VIDEO_CHAT_INVITE + 1;
    long long key = aboutTarget && message.targetId ? message.targetId : message.senderKey;
    if (!key) return;
    NoshiPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:key]];
    if (key > 0 && !person) {
        [_router openProfileOfUser:key inMessage:message.messageId dialog:_dialog];
        return;
    }
    [self openSender:person key:key messageId:message.messageId];
}

/* the line "forwarded from" opens the profile or the channel of whoever wrote the message, as in exteraGram; one who hid the link to their account cannot be opened,
   and the plate says so */
- (void)messageCellDidTapForward:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    long long key = message.forwardKey;
    if (!key) {
        NSString *name = NoshiForwardName(message, _people);
        NoshiShowNotice(nil, name.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.forward.hidden.named", nil), name] : NSLocalizedString(@"chat.forward.hidden", nil));
        return;
    }
    NoshiPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:key]];
    if (key > 0 && !person) {
        [_router openProfileOfUser:key inMessage:message.messageId dialog:_dialog];
        return;
    }
    [self openSender:person key:key messageId:message.messageId];
}

- (void)openSender:(NoshiPerson *)person key:(long long)key messageId:(int32_t)messageId {
    /* the group itself wrote it: its own profile is the place to go */
    if (!key) {
        [self openProfileGifts];
        return;
    }
    if (!person) return;
    if (key > 0 && !person.accessHash) {
        [_router openProfileOfUser:key inMessage:messageId dialog:_dialog];
        return;
    }
    if (key < 0 && !person.accessHash) {
        NoshiWeakReference *weak = _weak;
        [_session loadChannelSender:-key ofMessage:messageId inDialog:_dialog completion:^(NoshiPerson *sender, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat || chat.navigationController.topViewController != chat) return;
            if (errorName) {
                [chat toast:[NoshiLinkRouter textForError:errorName]];
                return;
            }
            [chat->_people setObject:sender forKey:[NSNumber numberWithLongLong:key]];
            [chat rebuildItems];
            [chat openSender:sender key:key messageId:messageId];
        }];
        return;
    }
    NoshiDialog *dialog = nil;
    if (key > 0) dialog = [NoshiDialog dialogWithPerson:person];
    else {
        noshi_dialog_row row;
        memset(&row, 0, sizeof(row));
        row.peer_kind = 3;
        row.peer_id = -key;
        row.peer_hash = person.accessHash;
        row.kind = NOSHI_DIALOG_CHANNEL;
        row.verified = person.verified;
        if (person.photo) row.photo = person.photo.ref;
        snprintf(row.title, sizeof(row.title), "%s", person.name.UTF8String);
        dialog = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
    }
    if (!dialog) {
        [self toast:NSLocalizedString(@"error.internal", nil)];
        return;
    }
    [_input.textView resignFirstResponder];
    UIViewController *profile = key > 0
        ? [[[NoshiUserProfileController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease]
        : [[[NoshiChannelProfileController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}

#pragma mark recording

/* the round video is limited to a minute, as the other clients limit it */
#define ROUND_SECONDS_MAX 60.0
#define ROUND_PREVIEW_SIDE 240.0
/* the room the circle keeps above and under itself, and the least it is drawn at before the keyboard has to give way */
#define ROUND_PREVIEW_TOP 60.0
#define ROUND_PREVIEW_GAP 8.0
#define ROUND_PREVIEW_MIN 96.0

static UIImage *NoshiRoundTorchImage(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22, 22), NO, 0);
    UIBezierPath *bolt = [UIBezierPath bezierPath];
    [bolt moveToPoint:CGPointMake(12, 1)];
    [bolt addLineToPoint:CGPointMake(4, 12)];
    [bolt addLineToPoint:CGPointMake(10, 12)];
    [bolt addLineToPoint:CGPointMake(8, 21)];
    [bolt addLineToPoint:CGPointMake(18, 9)];
    [bolt addLineToPoint:CGPointMake(12, 9)];
    [bolt closePath];
    [color setFill];
    [bolt fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)showRecordingFailure:(NSString *)reason {
    Class alertClass = NoshiAlertClass();
    NSString *text = reason.length ? [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"chat.record.unavailable", nil), reason]
                                   : NSLocalizedString(@"chat.record.unavailable", nil);
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

/* a swipe from the edge while a voice note or a video message is being recorded would drag the screen away, and the finger that holds the record button often starts near it */
- (BOOL)blocksBackSwipe {
    return _voice != nil || _roundRecorder != nil;
}

- (BOOL)inputBar:(NoshiInputBar *)bar didBeginRecording:(NoshiRecordMode)mode {
    (void)bar;
    if (_voice || _roundRecorder) return NO;
    [self.view endEditing:YES];
    /* before the recorder takes the audio session: switching to the record category under a playing song cuts it off without a pause, and it would never come back */
    NoshiMusicPlayer *music = [NoshiMusicPlayer sharedPlayer];
    [music pauseForRecording];
    if (mode == NoshiRecordVoice) {
        _voice = [[NoshiVoiceRecorder alloc] init];
        if (![_voice start]) {
            [_voice release];
            _voice = nil;
            [music resumeAfterRecording];
            [self showRecordingFailure:nil];
            return NO;
        }
    } else {
        _roundRecorder = [[NoshiRoundRecorder alloc] init];
        if (![_roundRecorder start]) {
            NSString *reason = [[_roundRecorder.failure copy] autorelease];
            [_roundRecorder release];
            _roundRecorder = nil;
            [music resumeAfterRecording];
            [self showRecordingFailure:reason];
            return NO;
        }
        [self showRoundPreview];
    }
    _recordTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(recordTick) userInfo:nil repeats:YES] retain];
    return YES;
}

/* the screen behind the picture dims while the clip records; the input bar stays above the shade with its record button and hints */
- (void)showRoundShade {
    _roundShade = [[UIView alloc] initWithFrame:self.view.bounds];
    _roundShade.backgroundColor = [UIColor blackColor];
    _roundShade.alpha = 0;
    _roundShade.userInteractionEnabled = NO;
    _roundShade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:_roundShade belowSubview:_input];
    [UIView animateWithDuration:0.2 animations:^{ _roundShade.alpha = 0.5; }];
    _roundGlow = [[NoshiRoundGlow alloc] initWithFrame:self.view.bounds];
    _roundGlow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:_roundGlow belowSubview:_input];
    _roundFlash = NO;
}

- (void)removeRoundShade {
    NoshiRoundGlow *glow = _roundGlow;
    _roundGlow = nil;
    _roundFlash = NO;
    if (glow) {
        [glow setLit:NO];
        /* the light fades for 0.24 s, and the view holds the screen brightness until it is released */
        [glow performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:0.3];
        [glow performSelector:@selector(release) withObject:nil afterDelay:0.35];
    }
    UIView *shade = _roundShade;
    _roundShade = nil;
    if (!shade) return;
    [UIView animateWithDuration:0.2 animations:^{ shade.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [shade removeFromSuperview];
        [shade release];
    }];
}

/* the picture grows out of the record button, overshoots a little and settles, as the other clients do it */
- (void)showRoundPreview {
    [self showRoundShade];
    CGSize size = self.view.bounds.size;
    /* the keyboard is another window and stays over the chat, so a circle that reaches down to it is half hidden: with the keyboard up the picture takes the room
       between the top of the screen and the input bar, which stands right over the keys */
    _roundSide = MIN(ROUND_PREVIEW_SIDE, MAX(ROUND_PREVIEW_MIN, _input.frame.origin.y - ROUND_PREVIEW_GAP - ROUND_PREVIEW_TOP));
    CGRect frame = CGRectMake((size.width - _roundSide) / 2, MAX(ROUND_PREVIEW_TOP, (_input.frame.origin.y - _roundSide) / 2), _roundSide, _roundSide);
    _roundPreview = [[UIView alloc] initWithFrame:frame];
    UIView *disc = [[[UIView alloc] initWithFrame:_roundPreview.bounds] autorelease];
    disc.layer.cornerRadius = _roundSide / 2;
    disc.layer.masksToBounds = YES;
    disc.layer.borderWidth = 3;
    disc.layer.borderColor = NoshiColorAccent().CGColor;
    disc.backgroundColor = [UIColor blackColor];
    CALayer *picture = _roundRecorder.previewLayer;
    picture.frame = disc.bounds;
    [disc.layer addSublayer:picture];
    [_roundPreview addSubview:disc];
    UIImageView *flip = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolCameraFlip, 22, [UIColor whiteColor])] autorelease];
    flip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    flip.contentMode = UIViewContentModeCenter;
    flip.frame = CGRectMake(_roundSide * 0.7, _roundSide * 0.7, 36, 36);
    flip.layer.cornerRadius = 18;
    [_roundPreview addSubview:flip];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(flipRoundCamera)] autorelease];
    [disc addGestureRecognizer:tap];
    _roundTorch = [UIButton buttonWithType:UIButtonTypeCustom];
    _roundTorch.frame = CGRectMake(_roundSide * 0.7, _roundSide * 0.14, 40, 40);
    _roundTorch.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _roundTorch.layer.cornerRadius = 20;
    _roundTorch.accessibilityLabel = NSLocalizedString(@"chat.round.torch", nil);
    [_roundTorch addTarget:self action:@selector(toggleRoundTorch) forControlEvents:UIControlEventTouchUpInside];
    [_roundPreview addSubview:_roundTorch];
    [self refreshRoundTorch];
    UIPinchGestureRecognizer *pinch = [[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchedRoundPreview:)] autorelease];
    [_roundPreview addGestureRecognizer:pinch];
    [self.view addSubview:_roundPreview];

    CGPoint origin = [_input recordButtonCenterInView:self.view];
    CGPoint center = _roundPreview.center;
    CGAffineTransform small = CGAffineTransformScale(CGAffineTransformMakeTranslation(origin.x - center.x, origin.y - center.y), 0.1, 0.1);
    _roundPreview.alpha = 0;
    _roundPreview.transform = small;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _roundPreview.alpha = 1;
        _roundPreview.transform = CGAffineTransformMakeScale(1.07, 1.07);
    } completion:^(BOOL finished) {
        (void)finished;
        [UIView animateWithDuration:0.1 animations:^{ _roundPreview.transform = CGAffineTransformIdentity; }];
    }];
}

/* the circle dims and shrinks a little while the camera is swapped (the picture goes black for a moment while the
   session is held) */
- (void)flipRoundCamera {
    if (!_roundRecorder || !_roundPreview || _roundFlipping || _roundTorchBusy) return;
    _roundFlipping = YES;
    [self refreshRoundTorch];
    UIView *preview = _roundPreview;
    UIView *disc = [preview.subviews count] ? [preview.subviews objectAtIndex:0] : nil;
    UIView *flip = [preview.subviews count] > 1 ? [preview.subviews objectAtIndex:1] : nil;
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        disc.alpha = 0.25f;
        disc.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
        flip.transform = CGAffineTransformMakeRotation((CGFloat)M_PI);
    } completion:nil];
    NoshiWeakReference *weak = _weak;
    [_roundRecorder switchCameraWithCompletion:^(BOOL switched) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        chat->_roundFlipping = NO;
        [chat applyRoundFlash];
        [chat refreshRoundTorch];
        /* a little later than the swap, so the first frame of the new camera is already in the layer */
        [UIView animateWithDuration:0.3 delay:switched ? 0.12 : 0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            disc.alpha = 1;
            disc.transform = CGAffineTransformIdentity;
            flip.transform = CGAffineTransformMakeRotation(0);
        } completion:nil];
    }];
}

- (void)refreshRoundTorch {
    _roundTorch.hidden = !_roundRecorder || _roundFlipping || !(_roundRecorder.canUseTorch || _roundRecorder.usesFrontCamera);
    _roundTorch.enabled = !_roundTorchBusy;
    [_roundTorch setImage:NoshiRoundTorchImage(_roundFlash ? NoshiColorAccent() : [UIColor whiteColor]) forState:UIControlStateNormal];
    _roundTorch.accessibilityValue = NSLocalizedString(_roundFlash ? @"chat.round.torch.on" : @"chat.round.torch.off", nil);
}

/* the front camera has no torch, so its flash is the light of the screen; the back camera lights its torch, and a camera swap carries the choice over */
- (void)applyRoundFlash {
    if (!_roundRecorder) return;
    if (_roundRecorder.usesFrontCamera) {
        [_roundGlow setLit:_roundFlash];
        return;
    }
    [_roundGlow setLit:NO];
    if (_roundRecorder.torchOn == _roundFlash || !_roundRecorder.canUseTorch) return;
    _roundTorchBusy = YES;
    NoshiRoundRecorder *recorder = _roundRecorder;
    NoshiWeakReference *weak = _weak;
    [recorder setTorchOn:_roundFlash completion:^(BOOL success) {
        NoshiChatController *chat = weak.target;
        if (!chat || chat->_roundRecorder != recorder) return;
        chat->_roundTorchBusy = NO;
        if (!success) {
            chat->_roundFlash = recorder.torchOn;
            NoshiShowNotice(nil, NSLocalizedString(@"chat.round.torch.failed", nil));
        }
        [chat refreshRoundTorch];
    }];
}

- (void)toggleRoundTorch {
    if (!_roundRecorder || _roundFlipping || _roundTorchBusy) return;
    _roundFlash = !_roundFlash;
    [self applyRoundFlash];
    [self refreshRoundTorch];
}

/* two fingers on the circle zoom the camera, and a small label says how far; ios 7 and later, where the lens has the zoom */
- (void)pinchedRoundPreview:(UIPinchGestureRecognizer *)pinch {
    if (!_roundRecorder || !_roundRecorder.canZoom) return;
    if (pinch.state == UIGestureRecognizerStateBegan) _roundZoomStart = _roundRecorder.zoom;
    if (pinch.state != UIGestureRecognizerStateBegan && pinch.state != UIGestureRecognizerStateChanged) return;
    [_roundRecorder setZoom:_roundZoomStart * pinch.scale];
    CGFloat shown = MAX(1, MIN(5, _roundZoomStart * pinch.scale));
    if (!_roundZoomLabel) {
        _roundZoomLabel = [[UILabel alloc] init];
        _roundZoomLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
        _roundZoomLabel.textColor = [UIColor whiteColor];
        _roundZoomLabel.font = NoshiFontSemibold(13);
        _roundZoomLabel.textAlignment = NoshiTextAlignmentCenter;
        _roundZoomLabel.layer.cornerRadius = 11;
        _roundZoomLabel.layer.masksToBounds = YES;
        _roundZoomLabel.frame = CGRectMake((_roundSide - 52) / 2, 14, 52, 22);
        [_roundPreview addSubview:_roundZoomLabel];
    }
    _roundZoomLabel.text = [NSString stringWithFormat:@"%.1f\u00d7", shown];
    _roundZoomLabel.alpha = 1;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideRoundZoomLabel) object:nil];
    [self performSelector:@selector(hideRoundZoomLabel) withObject:nil afterDelay:0.9];
}

- (void)hideRoundZoomLabel {
    [UIView animateWithDuration:0.25 animations:^{ _roundZoomLabel.alpha = 0; }];
}

/* the picture flies back into the button when it is sent */
- (void)dismissRoundPreviewSent:(BOOL)sent {
    UIView *preview = _roundPreview;
    _roundPreview = nil;
    _roundTorch = nil;
    _roundTorchBusy = NO;
    if (!preview) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideRoundZoomLabel) object:nil];
    [_roundZoomLabel release];
    _roundZoomLabel = nil;
    CGPoint center = preview.center;
    CGPoint target;
    if (sent) {
        target = [_input recordButtonCenterInView:self.view];
    } else {
        BOOL leaves = _roundRecorder.elapsed > 0.3;
        target = CGPointMake(leaves ? 24 : center.x, CGRectGetMidY(_input.frame));
    }
    CGAffineTransform gone = CGAffineTransformScale(CGAffineTransformMakeTranslation(target.x - center.x, target.y - center.y), 0.1, 0.1);
    preview.userInteractionEnabled = NO;
    [UIView animateWithDuration:sent ? 0.28 : 0.18 delay:0 options:sent ? UIViewAnimationOptionCurveEaseIn : UIViewAnimationOptionCurveEaseOut animations:^{
        preview.alpha = 0;
        preview.transform = gone;
    } completion:^(BOOL finished) {
        (void)finished;
        [preview removeFromSuperview];
        [preview release];
    }];
}

- (void)recordTick {
    NSTimeInterval elapsed = _voice ? _voice.elapsed : _roundRecorder.elapsed;
    [_input setRecordingElapsed:elapsed];
    /* a note that reaches the limit of the encoder goes by itself, a second short of it */
    if ((_roundRecorder && elapsed >= ROUND_SECONDS_MAX) || (_voice && elapsed >= NOSHI_VOICE_SECONDS_MAX - 1)) {
        /* the minute is up: the clip goes now, and the hold that is still down ends without a second send */
        [self finishRecordingCancelled:NO];
        [_input releaseHold];
    }
}

- (void)stopRecordTimer {
    [_recordTimer invalidate];
    [_recordTimer release];
    _recordTimer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideRoundZoomLabel) object:nil];
    [_roundZoomLabel release];
    _roundZoomLabel = nil;
    [_roundPreview removeFromSuperview];
    [_roundPreview release];
    _roundPreview = nil;
    _roundTorch = nil;
    _roundTorchBusy = NO;
    [self removeRoundShade];
}

/* the screen goes away or the app is left: whatever was recording is dropped */
- (void)discardRecording {
    [self stopRecordTimer];
    [_voice cancel];
    [_voice release];
    _voice = nil;
    [_roundRecorder cancel];
    [_roundRecorder release];
    _roundRecorder = nil;
    [[NoshiMusicPlayer sharedPlayer] resumeAfterRecording];
}

- (void)inputBar:(NoshiInputBar *)bar didFinishRecordingCancelled:(BOOL)cancelled {
    /* the choice of the chip belongs to this recording alone: it is read now and the chip goes back to off */
    _recordingOneTime = !cancelled && bar.oneTimeRecording;
    [bar clearOneTimeRecording];
    [self finishRecordingCancelled:cancelled];
}

- (void)finishRecordingCancelled:(BOOL)cancelled {
    if (!_voice && !_roundRecorder) return;
    [self dismissRoundPreviewSent:!cancelled];
    if (cancelled) {
        [self discardRecording];
        return;
    }
    NoshiWeakReference *weak = _weak;
    BOOL once = _recordingOneTime;
    _recordingOneTime = NO;
    NoshiVoiceRecorder *voice = _voice;
    NoshiRoundRecorder *round = _roundRecorder;
    _voice = nil;
    _roundRecorder = nil;
    [self stopRecordTimer];
    [[NoshiMusicPlayer sharedPlayer] resumeAfterRecording];
    if (voice) {
        [voice finishWithCompletion:^(NSString *path, int32_t durationMs, NSData *waveform) {
            NoshiChatController *chat = weak.target;
            if (path && chat) [chat sendRecordingAtPath:path durationMs:durationMs side:0 waveform:waveform viewOnce:once];
            else if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            else if (voice.failed) NoshiGiftAlert(nil, NSLocalizedString(@"chat.voice.failed", nil));
            [voice release];
        }];
    } else {
        [round finishWithCompletion:^(NSString *path, int32_t durationMs, int32_t side) {
            NoshiChatController *chat = weak.target;
            if (path && chat) [chat sendRecordingAtPath:path durationMs:durationMs side:side waveform:nil viewOnce:once];
            else if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [round release];
        }];
    }
}

- (void)sendRecordingAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side waveform:(NSData *)waveform viewOnce:(BOOL)once {
    NSString *file = [[path copy] autorelease];
    NSData *bars = [[waveform copy] autorelease];
    /* a recording nobody wants goes away with its file */
    [self askFirst:NoshiChatFlagAskRecording message:NSLocalizedString(side > 0 ? @"chat.ask.round" : @"chat.ask.voice", nil) action:NSLocalizedString(@"chat.ask.record.action", nil) then:^{
        [self sendConfirmedRecordingAtPath:file durationMs:durationMs side:side waveform:bars viewOnce:once];
    } declined:^{
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    }];
}

- (void)sendConfirmedRecordingAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side waveform:(NSData *)waveform viewOnce:(BOOL)once {
    NoshiOutgoing *outgoing = [[[NoshiOutgoing alloc] init] autorelease];
    outgoing->kind = side > 0 ? NoshiOutgoingRound : NoshiOutgoingVoice;
    outgoing->path = [path copy];
    outgoing->name = [path.lastPathComponent copy];
    outgoing->durationMs = durationMs;
    outgoing->width = side;
    outgoing->height = side;
    outgoing->waveform = [waveform copy];
    outgoing->temporary = YES;
    outgoing->viewOnce = once;
    [self sendOutgoing:outgoing];
}

/* the message shows at once as pending, and the file or point goes up behind it */
/* several photos and videos at once go out as one album: a pending message for each shows at once, and one request sends them together */
- (void)sendAlbum:(NSArray *)outgoings {
    /* telegram takes ten to an album: more go out as several, and the answer target stays for each */
    const NSUInteger piece = 10;
    int32_t reply = _replyToId;
    for (NSUInteger at = 0; at < outgoings.count; at += piece) {
        NSArray *part = [outgoings subarrayWithRange:NSMakeRange(at, MIN(piece, outgoings.count - at))];
        _replyToId = reply;
        if (part.count == 1) [self sendOutgoing:[part objectAtIndex:0]];
        else [self sendAlbumPart:part];
    }
}

- (void)sendAlbumPart:(NSArray *)outgoings {
    [self leaveWindow];
    int32_t now = (int32_t)[[NSDate date] timeIntervalSince1970];
    NSMutableArray *messages = [NSMutableArray arrayWithCapacity:outgoings.count], *randomIds = [NSMutableArray arrayWithCapacity:outgoings.count];
    long long albumNumber = [self newRandomId];
    for (NoshiOutgoing *outgoing in outgoings) {
        long long randomId = [self newRandomId];
        outgoing->replyTo = _replyToId;
        NoshiMessage *message = [NoshiMessage pendingOutgoing:outgoing randomId:randomId date:now];
        message.sendReplyTo = _replyToId;
        message.state = NoshiMessageStateSending;
        message.groupedId = albumNumber;
        message.sentAfterId = [self newestLoadedId];
        [messages addObject:message];
        [randomIds addObject:[NSNumber numberWithLongLong:randomId]];
        if (_dialog.kind == NOSHI_DIALOG_CHANNEL) [message showAsChannelPost];
        [_local addObject:message];
    }
    [self cancelCompose];
    _stickToBottom = YES;
    [_table setHidden:NO];
    [self showStatus:nil retry:NO];
    [self rebuildItems];
    NoshiWeakReference *weak = _weak;
    [_session sendAlbumOfOutgoings:outgoings toDialog:_dialog randomIds:randomIds completion:^(NSArray *messageIds, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        for (NSUInteger i = 0; i < messages.count; ++i) {
            [chat didSend:[messages objectAtIndex:i] messageId:messageIds ? [[messageIds objectAtIndex:i] intValue] : 0 error:errorName];
        }
    }];
}

- (void)sendOutgoing:(NoshiOutgoing *)outgoing {
    NoshiMessage *message = [NoshiMessage pendingOutgoing:outgoing randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    [self afterAppendingLocal:message];
    [self dispatchLocal:message];
}

- (void)inputBarDidTapSend:(NoshiInputBar *)bar {
    [self sendComposedFromBar:bar silent:NO];
}

/* the hold on the send button with words in the field: send without a sound, or send later; an edit in progress has neither */
- (void)inputBarDidHoldSend:(NoshiInputBar *)bar {
    if (_editingId || ![[bar trimmedText] length]) return;
    NoshiWeakReference *weak = _weak;
    /* the effects are for a private chat with a person; a Premium effect is offered to a Premium account only */
    NSMutableArray *effects = nil;
    if (_dialog.kind == NOSHI_DIALOG_USER && !_dialog.saved && !_pinnedList) {
        BOOL premium = [_session ownPerson].premium;
        effects = [NSMutableArray array];
        for (NoshiMessageEffect *effect in _messageEffects) if (premium || !effect.premium) [effects addObject:effect];
    }
    /* a sheet from the bottom stands under the keyboard that is up while the words are written, so the card is drawn right over the button */
    UIView *host = self.view;
    [NoshiSendMenu presentAboveRect:[bar sendButtonFrameInView:host] inView:host effects:effects handler:^(NoshiSendMenuChoice choice, long long effectId) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (choice == NoshiSendMenuSilent) {
            [chat sendComposedFromBar:bar silent:YES];
        } else if (choice == NoshiSendMenuLater) {
            [chat chooseTimeToSendFromBar:bar];
        } else {
            chat->_nextSendEffect = effectId;
            [chat sendComposedFromBar:bar silent:NO];
            chat->_nextSendEffect = 0;
        }
    }];
}

/* the list of effects is asked for when a private chat opens, so the hold on the send button finds it in */
- (void)playMessageEffect:(long long)effectId {
    if (!_visible) return;
    NoshiMessageEffect *effect = [NoshiMessageEffect effectWithId:effectId];
    if (effect) [NoshiMessageEffectPlayer playEffect:effect inView:self.view media:_media];
}

- (void)loadMessageEffectsIfPrivate {
    if (_dialog.kind != NOSHI_DIALOG_USER || _dialog.saved || _pinnedList || _messageEffects) return;
    NoshiWeakReference *weak = _weak;
    [_session loadMessageEffects:^(NSArray *effects, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: the message effects could not be loaded: %@", errorName);
            return;
        }
        [chat->_messageEffects release];
        chat->_messageEffects = [effects retain];
    }];
}

- (void)chooseTimeToSendFromBar:(NoshiInputBar *)bar {
    NoshiWeakReference *weak = _weak;
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"chat.remind.hour", nil), NSLocalizedString(@"chat.remind.three", nil),
                       NSLocalizedString(@"chat.remind.tomorrow", nil), NSLocalizedString(@"chat.remind.week", nil), nil];
    [NoshiSheet presentInView:self.view title:NSLocalizedString(@"chat.send.later", nil) message:nil options:titles destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        NoshiChatController *chat = weak.target;
        if (chat) [chat scheduleComposedFromBar:bar at:NoshiReminderDate(index)];
    }];
}

/* the server keeps the message and sends it at the time; it is not in the chat until then, so there is no pending copy to draw */
- (void)scheduleComposedFromBar:(NoshiInputBar *)bar at:(NSDate *)when {
    NSString *text = [bar trimmedText];
    if (!text.length || !when) return;
    NSArray *entities = [bar sendEntities];
    int32_t replyTo = _replyToId ? _replyToId : [_bots replyTargetForText];
    NoshiWeakReference *weak = _weak;
    [_session scheduleText:text entities:entities atDate:(int32_t)[when timeIntervalSince1970] toDialog:_dialog replyTo:replyTo completion:^(NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"noshigram: the message was not scheduled: %@", errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [chat toast:NSLocalizedString(@"chat.send.scheduled", nil)];
    }];
    [bar clear];
    [_bots didSendText];
    [self cancelCompose];
    [self saveDraftNow];
}

- (void)sendComposedFromBar:(NoshiInputBar *)bar silent:(BOOL)silent {
    NSString *text = [bar trimmedText];
    if (!text.length) return;
    if (_editingId) {
        [self commitEditWithText:text];
        return;
    }
    NSArray *entities = [bar sendEntities];
    int32_t replyTo = _replyToId ? _replyToId : [_bots replyTargetForText];
    NSString *quote = _replyToId ? [[_replyQuote copy] autorelease] : nil;
    int32_t quoteOffset = _replyQuoteOffset;
    [bar clear];
    [_bots didSendText];
    [self cancelCompose];
    [self sendText:text entities:entities replyTo:replyTo quote:quote quoteOffset:quoteOffset silent:silent];
    /* the message is on its way, and the draft that held its words goes at once instead of after the pause */
    [self saveDraftNow];
}

- (void)afterAppendingLocal:(NoshiMessage *)message {
    [self leaveWindow];
    if (!_voice) NoshiPlayInChatSound(NO);
    if (_dialog.kind == NOSHI_DIALOG_CHANNEL) [message showAsChannelPost];
    if (!message.sendReplyTo) message.sendReplyTo = _replyToId;
    message.sentAfterId = [self newestLoadedId];
    [self cancelComposeAnimated:NO];
    [_local addObject:message];
    _interacting = NO;
    _stickToBottom = YES;
    [_table setHidden:NO];
    [self showStatus:nil retry:NO];
    [self rebuildItems];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities {
    [self sendText:text entities:entities replyTo:0];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo {
    [self sendText:text entities:entities replyTo:replyTo quote:nil quoteOffset:-1];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset {
    [self sendText:text entities:entities replyTo:replyTo quote:quote quoteOffset:quoteOffset silent:NO];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset silent:(BOOL)silent {
    [self appendPendingText:text entities:entities replyTo:replyTo quote:quote quoteOffset:quoteOffset silent:silent];
}

/* the server refuses a text over 4096 units (8192 with Premium), so a longer one goes as several messages cut at the same places as the Android client */
- (void)appendPendingText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo quote:(NSString *)plannedQuote quoteOffset:(int32_t)plannedOffset silent:(BOOL)silent {
    NSArray *parts = NoshiTextPartsForLimit(text, entities, [_session ownPerson].premium ? NOSHI_MESSAGE_LIMIT_PREMIUM : NOSHI_MESSAGE_LIMIT);
    if (!parts) {
        NoshiShowNotice(nil, NSLocalizedString(@"chat.send.toolong", nil));
        return;
    }
    if (!parts.count) return;
    BOOL first = YES;
    for (NoshiTextPart *part in parts) {
        NoshiMessage *message = [NoshiMessage pendingText:part.text entities:part.entities randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
        message.sendReplyTo = replyTo;
        message.sendSilent = silent;
        /* the effect, like the quote, belongs to the first message only */
        message.sendEffect = first ? _nextSendEffect : 0;
        /* the quote belongs to the first message only, the others answer the same message */
        message.sendQuote = first ? plannedQuote : nil;
        message.sendQuoteOffset = first ? plannedOffset : -1;
        first = NO;
        [self afterAppendingLocal:message];
        [self dispatchLocal:message];
    }
}

- (void)sendSticker:(NoshiMedia *)sticker {
    NoshiMessage *message = [NoshiMessage pendingSticker:sticker randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    [self afterAppendingLocal:message];
    [self dispatchLocal:message];
    [self promoteSetOfSticker:sticker];
}

/* the set a sticker came from goes to the front of the panel; a set the account does not have, or one that is
   first already, changes nothing */
- (void)promoteSetOfSticker:(NoshiMedia *)sticker {
    long long setId = sticker.stickerSetId;
    if (!setId || !NoshiChatDynamicPackOrder()) return;
    NoshiSession *session = _session;
    [_stickers loadSets:^(NSArray *sets, NSString *errorName) {
        (void)errorName;
        if (!sets.count || [(NoshiStickerSet *)[sets objectAtIndex:0] setId] == setId) return;
        for (NoshiStickerSet *set in sets) {
            if (set.setId != setId) continue;
            [session moveStickerSetToTop:set among:sets completion:^(NSString *error) {
                if (error) NSLog(@"noshigram: the sticker set did not move to the front: %@", error);
            }];
            return;
        }
    }];
}

/* sends what the screen holds for a message that has not gone out, or whose last try failed */
- (void)dispatchLocal:(NoshiMessage *)message {
    NoshiWeakReference *weak = _weak;
    message.state = NoshiMessageStateSending;
    NoshiSession *session = _session;
    NoshiDialog *dialog = _dialog;
    NoshiSendCompletion done = ^(int32_t messageId, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) {
            /* the chat was left while this went up, and a send that fails now would vanish with its screen */
            if (errorName) {
                message.state = NoshiMessageStateFailed;
                [session keepUnsentMessage:message forDialog:dialog];
            }
            return;
        }
        [chat didSend:message messageId:messageId error:errorName];
    };
    NoshiOutgoing *out = message.pendingSend;
    if (out) {
        [_session sendOutgoing:out toDialog:_dialog randomId:message.randomId replyTo:message.sendReplyTo completion:done];
    } else if (message.media.kind == NOSHI_PREVIEW_STICKER || message.media.kind == NOSHI_PREVIEW_GIF) [_session sendSticker:message.media toDialog:_dialog randomId:message.randomId replyTo:message.sendReplyTo completion:done];
    else [_session sendText:message.text entities:message.entities toDialog:_dialog randomId:message.randomId replyTo:message.sendReplyTo quote:message.sendQuote quoteOffset:message.sendQuoteOffset silent:message.sendSilent effect:message.sendEffect completion:done];
}

- (void)didSend:(NoshiMessage *)message messageId:(int32_t)messageId error:(NSString *)errorName {
    if (![_local containsObject:message]) return;
    if ([errorName hasPrefix:@"ALLOW_PAYMENT_REQUIRED_"]) {
        /* the chat charges for each message: the server names the price, and the message goes again with it once the person agrees */
        long long stars = [[errorName substringFromIndex:[@"ALLOW_PAYMENT_REQUIRED_" length]] longLongValue];
        message.state = NoshiMessageStateFailed;
        [self rebuildItems];
        if (stars <= 0) return;
        NoshiWeakReference *weak = _weak;
        NoshiShowAlert(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.paidmessage.confirm", nil), stars],
                         [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"chat.paidmessage.button", nil), nil], 0, NO,
                         ^(NSInteger index, NSString *text) {
            (void)text;
            NoshiChatController *chat = weak.target;
            if (!chat || index != 1 || ![chat->_local containsObject:message]) return;
            [chat->_session approvePaidMessages:stars ofDialog:chat->_dialog];
            [chat dispatchLocal:message];
        });
        return;
    }
    if (errorName) {
        NSLog(@"noshigram: sending to chat %lld failed: %@", _dialog.peerId, errorName);
        message.state = NoshiMessageStateFailed;
    } else {
        message.state = NoshiMessageStateSent;
        message.messageId = messageId;
        if (message.sendEffect) [self playMessageEffect:message.sendEffect];
        NoshiOutgoing *sent = message.pendingSend;
        if (sent && sent->temporary && sent->path && (sent->viewOnce || sent->kind == NoshiOutgoingPhoto))
            [[NSFileManager defaultManager] removeItemAtPath:sent->path error:NULL];
        /* the server's copy may have arrived already */
        NoshiMessage *server = messageId > 0 ? [_server objectForKey:[NSNumber numberWithInt:messageId]] : nil;
        if (server) {
            [self keepUploadedMediaOf:message server:server];
            [_local removeObject:message];
            _localReplaced = YES;
        }
    }
    [self rebuildItems];
}

- (void)messageCellDidTapSticker:(NoshiMessageCell *)cell {
    NoshiWeakReference *weak = _weak;
    [NoshiStickerPackSheet presentInView:self.view forSticker:cell.item.message.media session:_session media:_media sender:^(NoshiMedia *sticker) {
        NoshiChatController *chat = weak.target;
        if (chat && chat->_input.writable && !chat->_pinnedList) [chat sendSticker:sticker];
    }];
}

/* the sender looks at their own file while the other side has not: nothing is reported and nothing burns */
- (void)previewViewOnce:(NoshiMessage *)message {
    if (message.media.kind == NOSHI_PREVIEW_VOICE) {
        /* the player fetches by the file of the server, which a note that is still going up does not have */
        if (!message.media.file) {
            NoshiShowAlert(nil, NSLocalizedString(@"viewonce.preview.wait", nil), [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
            return;
        }
        NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
        if ([player isCurrentTrack:message.media]) [player togglePause];
        else [player playTrack:message.media queue:[NSArray arrayWithObject:message.media] media:_media];
        return;
    }
    [self dismissInput];
    NoshiMediaViewer *viewer = [[[NoshiMediaViewer alloc] initWithOneTimePreviewOfMessage:message media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

/* a one-time voice note plays through the player of the app, alone in its queue; the server hears that it was opened when the sound starts, and the card burns
   when the note is no longer the track of the player (it ended, or the person stopped it), which is when it is gone */
- (void)playViewOnceVoice:(NoshiMessage *)message {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    NoshiMedia *track = message.media;
    [_onceVoice release];
    _onceVoice = [track retain];
    _onceVoiceId = message.messageId;
    _onceVoiceOpened = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiMusicPlayerDidChangeNotification object:player];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onceVoiceChanged:) name:NoshiMusicPlayerDidChangeNotification object:player];
    [player playTrack:track queue:[NSArray arrayWithObject:track] media:_media];
}

- (void)endOnceVoice {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiMusicPlayerDidChangeNotification object:[NoshiMusicPlayer sharedPlayer]];
    [_onceVoice release];
    _onceVoice = nil;
}

- (void)onceVoiceChanged:(NSNotification *)note {
    (void)note;
    if (!_onceVoice) return;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    BOOL current = [player isCurrentTrack:_onceVoice];
    int32_t messageId = _onceVoiceId;
    if (current && player.state == NoshiMusicStateFailed) {
        NSLog(@"noshigram: the one-time voice note did not play, so it stays unopened");
        [self endOnceVoice];
        return;
    }
    if (current && player.state == NoshiMusicStatePlaying && !_onceVoiceOpened) {
        _onceVoiceOpened = YES;
        [_openedOnce addObject:[NSNumber numberWithInt:messageId]];
        NoshiMessage *message = [self messageWithId:messageId];
        message.viewOnceOpened = YES;
        [_session markContentsRead:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:_dialog completion:^(NSString *errorName) {
            if (errorName) NSLog(@"noshigram: the server was not told that a one-time voice note was heard: %@", errorName);
        }];
        return;
    }
    if (current) return;
    BOOL opened = _onceVoiceOpened;
    [self endOnceVoice];
    if (!opened) return;
    NoshiWeakReference *weak = _weak;
    for (NoshiMessageCell *visible in _table.visibleCells) {
        if ([visible isKindOfClass:[NoshiMessageCell class]] && visible.item.message.messageId == messageId) {
            [visible playBurnWithCompletion:^{ [(NoshiChatController *)weak.target rebuildItems]; }];
            return;
        }
    }
    [self rebuildItems];
}

/* a tap on the card of a one-time file: it opens in a viewer of its own, the server hears that it was opened when the picture is on the screen, and the card burns when the viewer is closed */
- (void)messageCellDidTapViewOnce:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    if (!NoshiMessageIsViewOnce(message)) return;
    /* the note that plays now pauses and resumes on a tap, even after the server has marked it opened */
    if (message.media.kind == NOSHI_PREVIEW_VOICE && _onceVoice && message.messageId == _onceVoiceId && [[NoshiMusicPlayer sharedPlayer] isCurrentTrack:_onceVoice]) {
        [[NoshiMusicPlayer sharedPlayer] togglePause];
        return;
    }
    if (message.outgoing) {
        if (NoshiViewOnceExpired(message)) {
            NoshiShowAlert(nil, NSLocalizedString(@"viewonce.seen", nil), [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
        } else {
            [self previewViewOnce:message];
        }
        return;
    }
    if (NoshiViewOnceExpired(message)) {
        NoshiShowAlert(nil, NSLocalizedString(@"viewonce.gone", nil), [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
        return;
    }
    if (message.messageId <= 0) return;
    if (message.media.kind == NOSHI_PREVIEW_VOICE) {
        [self playViewOnceVoice:message];
        return;
    }
    [self dismissInput];
    NoshiWeakReference *weak = _weak;
    int32_t messageId = message.messageId;
    NoshiMediaViewer *viewer = [[[NoshiMediaViewer alloc] initWithOneTimeMessage:message media:_media opened:^{
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        message.viewOnceOpened = YES;
        [chat->_openedOnce addObject:[NSNumber numberWithInt:messageId]];
        [chat->_session markContentsRead:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:chat->_dialog completion:^(NSString *errorName) {
            if (errorName) NSLog(@"noshigram: the server was not told that a one-time file was opened: %@", errorName);
        }];
    } closed:^{
        NoshiChatController *chat = weak.target;
        if (!chat || ![chat->_openedOnce containsObject:[NSNumber numberWithInt:messageId]]) return;
        /* the card burns where it stands, and the row is built again as an expired one once the sparks are gone */
        for (NoshiMessageCell *visible in chat->_table.visibleCells) {
            if ([visible isKindOfClass:[NoshiMessageCell class]] && visible.item.message.messageId == messageId) {
                [visible playBurnWithCompletion:^{ [(NoshiChatController *)weak.target rebuildItems]; }];
                return;
            }
        }
        [chat rebuildItems];
    }] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

/* paid media opens only after the stars are paid: the server quotes the price, the person confirms it, and the message is read again with its real media */
- (void)messageCellDidTapPaid:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    int32_t messageId = message.messageId;
    if (messageId <= 0 || message.media.kind != NOSHI_PREVIEW_PAID || _paidBusy) return;
    _paidBusy = YES;
    NoshiWeakReference *weak = _weak;
    [_session quoteUnlockingMediaOfMessageId:messageId inDialog:_dialog completion:^(NoshiPaymentQuote *quote, NSString *errorName) {
        NoshiChatController *chat = weak.target;
        if (!chat) return;
        if (!quote) {
            chat->_paidBusy = NO;
            NoshiShowNotice(nil, NoshiGiftErrorText(errorName));
            return;
        }
        /* the flag holds until the payment ends or the question is turned down, so a second tap cannot ask for a second payment */
        NoshiShowAlert(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.paid.confirm", nil), quote.stars],
                         [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"chat.paid.confirm.button", nil), nil], 0, NO,
                         ^(NSInteger index, NSString *text) {
            (void)text;
            NoshiChatController *current = weak.target;
            if (!current) return;
            if (index != 1) {
                current->_paidBusy = NO;
                return;
            }
            [current->_session payQuote:quote completion:^(NSString *payError) {
                NoshiChatController *paid = weak.target;
                if (!paid) return;
                if (payError) {
                    paid->_paidBusy = NO;
                    NoshiShowNotice(nil, NoshiGiftErrorText(payError));
                    return;
                }
                [paid->_session loadMessagesWithIds:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] ofDialog:paid->_dialog
                                         completion:^(NSArray *messages, NSString *loadError) {
                    NoshiChatController *reloaded = weak.target;
                    if (!reloaded) return;
                    reloaded->_paidBusy = NO;
                    if (!messages) {
                        NSLog(@"noshigram: paid media %d was bought but did not reload: %@", (int)messageId, loadError);
                        return;
                    }
                    [reloaded mergeMessages:messages];
                }];
            }];
        });
    }];
}

- (void)messageCellDidTapMedia:(NoshiMessageCell *)cell {
    NoshiMessage *selected = cell.tappedMediaMessage;
    if (selected.media.kind == NOSHI_PREVIEW_LOCATION && selected.media.location.valid) {
        [self dismissInput];
        NoshiLocationController *viewer=[[[NoshiLocationController alloc] initWithSession:_session dialog:_dialog location:selected.media.location selection:nil] autorelease];
        UINavigationController *navigation=[[[UINavigationController alloc] initWithRootViewController:viewer] autorelease];
        NoshiClassicStyleNavigationBar(navigation.navigationBar);
        [self presentViewController:navigation animated:YES completion:nil];
        return;
    }
    if (!noshi_media_opens_viewer(selected.media.kind)) return;
    [self dismissInput];
    NSMutableArray *messages = [NSMutableArray array];
    for (NoshiChatItem *item in _items) {
        /* an album brings all its pictures, in order */
        for (NoshiMessage *message in (item.albumMessages ? item.albumMessages : (item.message ? [NSArray arrayWithObject:item.message] : nil))) {
            noshi_preview_kind kind = message.media.kind;
            if (message.media.file && noshi_media_opens_viewer(kind) && !message.media.viewOnce) [messages addObject:message];
        }
    }
    /* the cell may still hold the message of a list that was rebuilt since, so the viewer is given the copy that is in the list */
    if (![messages containsObject:selected]) {
        NoshiMessage *current = nil;
        for (NoshiMessage *message in messages) if (message.messageId == selected.messageId) { current = message; break; }
        if (!current) return;
        selected = current;
    }
    NSMutableDictionary *senderNames = [NSMutableDictionary dictionary];
    for (NSNumber *key in _people) {
        NoshiPerson *person = [_people objectForKey:key];
        if (person.name.length) [senderNames setObject:person.name forKey:key];
    }
    NoshiMediaViewer *viewer = [[[NoshiMediaViewer alloc] initWithMessages:messages selected:selected media:_media
        senderNames:senderNames chatTitle:_dialog.title] autorelease];
    NoshiWeakReference *weakChat = [NoshiWeakReference referenceTo:self];
    viewer.showInChatHandler = ^(NoshiMessage *shown) {
        NoshiChatController *me = (NoshiChatController *)weakChat.target;
        if (me) [me jumpToMessageId:shown.messageId];
    };
    [self presentViewController:viewer animated:YES completion:nil];
}

/* a tap on the card of a gift opens the same detail as the profile shows; the chat has no say over what the gift may do, so it is read only */
- (void)messageCellDidTapGift:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    if (!message.gift) return;
    noshi_saved_gift row;
    memset(&row, 0, sizeof(row));
    row.gift = message.gift.row;
    row.from_id = message.fromId;
    row.date = message.date;
    snprintf(row.note, sizeof(row.note), "%s", [message.text UTF8String]);
    NoshiGiftDetailController *detail = [[[NoshiGiftDetailController alloc] initWithSession:_session gift:[NoshiSavedGift savedGiftWithRow:&row] mine:NO
                                                                                        avatars:_avatars media:_media] autorelease];
    detail.stickers = _stickers;
    [detail showInViewController:self];
}

/* a tap on a song plays it, and the songs of this chat from there on follow it; a tap on the one that plays pauses it */
- (void)messageCellDidTapAudio:(NoshiMessageCell *)cell {
    NoshiMedia *track = cell.item.message.media;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    if ([player isCurrentTrack:track] && player.state != NoshiMusicStateFailed) {
        [player togglePause];
        return;
    }
    [self playAudioTrack:track];
}

/* voice notes follow one another and songs follow songs, but a note does not lead into a song */
- (void)playAudioTrack:(NoshiMedia *)track {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    NSMutableArray *queue = [NSMutableArray array];
    for (NoshiChatItem *item in _items) {
        NoshiMedia *media = item.message.media;
        if (media.kind == track.kind && media.file) [queue addObject:media];
    }
    if (track.kind == NOSHI_PREVIEW_VOICE) {
        /* the player walks only voice notes, so a video message between two of them is started from here when the note before it ends */
        NoshiWeakReference *weak = _weak;
        player.voiceEndHandler = ^BOOL(NoshiMedia *ended) {
            NoshiChatController *me = weak.target;
            return me && [me voiceNoteEnded:ended];
        };
    }
    [player playTrack:track queue:queue media:_media];
}

/* the item after index that a note or a video message hands over to: another voice note or a video message with a file, one-time ones left alone */
- (NSUInteger)chainItemAfter:(NSUInteger)index {
    for (NSUInteger next = index + 1; next < _items.count; ++next) {
        NoshiChatItem *item = [_items objectAtIndex:next];
        NoshiMedia *media = item.message.media;
        if (!media.file) continue;
        if (item.kind == NoshiChatItemRound) return next;
        if (media.kind == NOSHI_PREVIEW_VOICE && !media.viewOnce) return next;
    }
    return NSNotFound;
}

/* the item before index that a note or a video message hands back to, by the same rule as the one after */
- (NSUInteger)chainItemBefore:(NSUInteger)index {
    for (NSUInteger previous = MIN(index, _items.count); previous > 0; --previous) {
        NoshiChatItem *item = [_items objectAtIndex:previous - 1];
        NoshiMedia *media = item.message.media;
        if (!media.file) continue;
        if (item.kind == NoshiChatItemRound) return previous - 1;
        if (media.kind == NOSHI_PREVIEW_VOICE && !media.viewOnce) return previous - 1;
    }
    return NSNotFound;
}

/* brings the item into view when it is off screen and starts it as a tap on it would; NO when a video message has no row to play in */
- (BOOL)startChainItemAtIndex:(NSUInteger)index {
    NoshiChatItem *item = [_items objectAtIndex:index];
    if (item.kind != NoshiChatItemRound) {
        [self playAudioTrack:item.message.media];
        return YES;
    }
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
    if (![[_table indexPathsForVisibleRows] containsObject:path]) {
        [_table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [_table layoutIfNeeded];
    }
    NoshiMessageCell *cell = (NoshiMessageCell *)[_table cellForRowAtIndexPath:path];
    [cell startRound];
    return cell != nil;
}

/* a voice note ended: when the next voice note or video message of the chat is a video message, it starts and the player stops; a voice note next is left to the
   player, whose queue is the voice notes of the chat in order */
- (BOOL)voiceNoteEnded:(NoshiMedia *)ended {
    if (NoshiChatFlagGet(NoshiChatFlagNoAutoNextVoice) || ended.viewOnce) return NO;
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        NoshiChatItem *candidate = [_items objectAtIndex:i];
        NoshiMedia *media = candidate.message.media;
        if (media.kind == NOSHI_PREVIEW_VOICE && [media.file.key isEqualToString:ended.file.key]) { index = i; break; }
    }
    if (index == NSNotFound) return NO;
    NSUInteger next = [self chainItemAfter:index];
    if (next == NSNotFound || ((NoshiChatItem *)[_items objectAtIndex:next]).kind != NoshiChatItemRound) return NO;
    [self startChainItemAtIndex:next];
    return YES;
}

/* a document that has come opens in the preview of the system, or offers the apps that take it; the cache names its files by key only, so a link with the real
   extension is what tells the system the type */
- (void)messageCell:(NoshiMessageCell *)cell didOpenFileAtPath:(NSString *)path name:(NSString *)name {
    [self openDocumentAtPath:path name:name fromCell:cell];
}

- (void)openDocumentAtPath:(NSString *)path name:(NSString *)name fromCell:(NoshiMessageCell *)cell {
    NSURL *url = NoshiNamedLink(path, name.length ? name : @"file.bin", @"document");
    if (!url) {
        NoshiGiftAlert(nil, NSLocalizedString(@"chat.file.open.failed", nil));
        return;
    }
    [self dismissInput];
    _document.delegate = nil;
    [_document release];
    _document = [[UIDocumentInteractionController interactionControllerWithURL:url] retain];
    _document.delegate = self;
    if ([_document presentPreviewAnimated:YES]) return;
    if (![_document presentOpenInMenuFromRect:cell.bounds inView:cell animated:YES]) NoshiGiftAlert(nil, NSLocalizedString(@"chat.file.open.failed", nil));
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    (void)controller;
    return self;
}

/* a video message that ended hands over to the next video message or voice note of the chat; a voice note starts only when the chat lets voice notes follow
   one another */
- (NSUInteger)chainIndexOfRoundKey:(NSString *)key {
    for (NSUInteger i = 0; i < _items.count; ++i) {
        NoshiChatItem *item = [_items objectAtIndex:i];
        if (item.kind == NoshiChatItemRound && [item.message.media.file.key isEqualToString:key]) return i;
    }
    return NSNotFound;
}

- (void)roundPlayback:(NoshiRoundPlayback *)playback didFinishKey:(NSString *)key {
    (void)playback;
    NSUInteger index = [self chainIndexOfRoundKey:key];
    if (index == NSNotFound) return;
    NSUInteger next = [self chainItemAfter:index];
    if (next == NSNotFound) return;
    if (((NoshiChatItem *)[_items objectAtIndex:next]).kind != NoshiChatItemRound && NoshiChatFlagGet(NoshiChatFlagNoAutoNextVoice)) return;
    [self startChainItemAtIndex:next];
}

/* the buttons of the strip and of the floating circle walk the video messages and voice notes of the chat from where the circle is */
- (BOOL)roundPlayback:(NoshiRoundPlayback *)playback stepFromKey:(NSString *)key direction:(NSInteger)direction {
    (void)playback;
    NSUInteger index = [self chainIndexOfRoundKey:key];
    if (index == NSNotFound) return NO;
    NSUInteger target = direction < 0 ? [self chainItemBefore:index] : [self chainItemAfter:index];
    return target != NSNotFound && [self startChainItemAtIndex:target];
}

/* the cross on a message that is going up: the upload stops and the pending message goes, as if it was never sent */
- (void)messageCellDidCancelSending:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    if (![_local containsObject:message] || message.state != NoshiMessageStateSending) return;
    [_session cancelSendWithRandomId:message.randomId];
    NoshiOutgoing *sent = message.pendingSend;
    if (sent && sent->temporary && sent->path) [[NSFileManager defaultManager] removeItemAtPath:sent->path error:NULL];
    [_local removeObject:message];
    [self rebuildItems];
}

- (void)messageCellDidTapFailed:(NoshiMessageCell *)cell {
    NoshiMessage *message = cell.item.message;
    if (![_local containsObject:message]) return;
    NoshiWeakReference *weak = _weak;
    NoshiShowAlert(nil, NSLocalizedString(@"chat.send.failed", nil),
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"chat.send.retry", nil), NSLocalizedString(@"chat.send.delete", nil), nil], 0, NO,
                     ^(NSInteger index, NSString *text) {
        (void)text;
        NoshiChatController *chat = weak.target;
        if (!chat || index < 1 || ![chat->_local containsObject:message]) return;
        if (index == 2) { [chat->_local removeObject:message]; [chat rebuildItems]; return; }
        [chat resendFailed:message];
    });
}

- (void)resendFailed:(NoshiMessage *)message {
    /* the failed copy goes and a new one with a new random id takes its place at the end */
    NoshiMessage *again = message.pendingSend
        ? [NoshiMessage pendingOutgoing:message.pendingSend randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]]
        : message.media.kind == NOSHI_PREVIEW_STICKER
        ? [NoshiMessage pendingSticker:message.media randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]]
        : [NoshiMessage pendingText:message.text entities:message.entities randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    again.sendReplyTo = message.sendReplyTo;
    again.sendQuote = message.sendQuote;
    again.sendQuoteOffset = message.sendQuoteOffset;
    again.sendSilent = message.sendSilent;
    again.sendEffect = message.sendEffect;
    [_local removeObject:message];
    [self afterAppendingLocal:again];
    [self dispatchLocal:again];
}

/* a link whose words are not its address: the message carries the address as an entity over other text */
- (BOOL)isHiddenLink:(NSString *)url inMessage:(NoshiMessage *)message {
    for (NoshiTextEntity *entity in message.entities) if ([entity.url isEqualToString:url]) return YES;
    return NO;
}

- (void)messageCell:(NoshiMessageCell *)cell didTapCode:(NoshiTextEntity *)entity {
    NSUInteger token = ++_codeCopyToken;
    NoshiMessage *message = cell.item.message;
    NSRange range = entity.range;
    if ((entity.style != NoshiTextStyleCode && entity.style != NoshiTextStylePre) || !range.length ||
        range.location > message.text.length || range.length > message.text.length - range.location) return;
    if (message.noForwards || _dialog.noForwards || _channelFull.dialog.noForwards) {
        [self toast:NSLocalizedString(@"chat.copy.restricted", nil)];
        return;
    }
    NSString *code = [message.text substringWithRange:range];
    NSString *source = message.text;
    int32_t messageId = message.messageId;
    if (_dialog.peerKind == 1 && !_dialog.saved) {
        NoshiWeakReference *weak = _weak;
        [_session loadFullUserOfDialog:_dialog completion:^(NoshiFullUser *user, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat || token != chat->_codeCopyToken) return;
            if (!user) {
                NoshiShowNotice(nil, [chat failureTextForError:errorName]);
            } else if (user.sharingRestricted) {
                [chat toast:NSLocalizedString(@"chat.copy.restricted", nil)];
            } else if ([chat codeCopyMessage:messageId stillMatches:source range:range style:entity.style]) {
                [UIPasteboard generalPasteboard].string = code;
                [chat toast:NSLocalizedString(@"profile.copied", nil)];
            }
        }];
    } else if (_dialog.peerKind == 3 && (!_channelFull || !_channelFull.membershipKnown)) {
        NoshiWeakReference *weak = _weak;
        [_session loadFullChannelOfDialog:_dialog completion:^(NoshiFullChannel *channel, NSString *errorName) {
            NoshiChatController *chat = weak.target;
            if (!chat || token != chat->_codeCopyToken) return;
            if (!channel) {
                NoshiShowNotice(nil, [chat failureTextForError:errorName]);
            } else if (!channel.membershipKnown) {
                NoshiShowNotice(nil, NSLocalizedString(@"chat.copy.unavailable", nil));
            } else if (channel.dialog.noForwards) {
                [chat toast:NSLocalizedString(@"chat.copy.restricted", nil)];
            } else if ([chat codeCopyMessage:messageId stillMatches:source range:range style:entity.style]) {
                [UIPasteboard generalPasteboard].string = code;
                [chat toast:NSLocalizedString(@"profile.copied", nil)];
            }
        }];
    } else {
        [UIPasteboard generalPasteboard].string = code;
        [self toast:NSLocalizedString(@"profile.copied", nil)];
    }
}

- (BOOL)codeCopyMessage:(int32_t)messageId stillMatches:(NSString *)source range:(NSRange)range style:(NoshiTextStyle)style {
    NoshiMessage *current = [self messageWithId:messageId];
    if (!current || current.noForwards || _dialog.noForwards || _channelFull.dialog.noForwards || ![current.text isEqualToString:source]) return NO;
    BOOL found = NO;
    noshi_entity spoilers[NOSHI_MESSAGE_ENTITIES_MAX];
    size_t count = 0;
    memset(spoilers, 0, sizeof(spoilers));
    for (NoshiTextEntity *entity in current.entities) {
        if (entity.style == style && NSEqualRanges(entity.range, range)) found = YES;
        if (entity.style != NoshiTextStyleSpoiler) continue;
        if (count == NOSHI_MESSAGE_ENTITIES_MAX || entity.range.location > INT32_MAX || entity.range.length > INT32_MAX) return NO;
        spoilers[count].kind = NOSHI_ENTITY_SPOILER;
        spoilers[count].offset = (int32_t)entity.range.location;
        spoilers[count++].length = (int32_t)entity.range.length;
    }
    return found && (current.spoilersRevealed || !noshi_code_has_hidden_spoiler(range.location, range.length, spoilers, count));
}

- (void)messageCell:(NoshiMessageCell *)cell didTapLink:(NSString *)url {
    NoshiWeakReference *weak = _weak;
    /* a name written over a user opens that user, whatever the words say */
    if ([url hasPrefix:@"noshigram-user:"]) {
        long long userId = [[url substringFromIndex:[@"noshigram-user:" length]] longLongValue];
        if (userId > 0) [_router openProfileOfUser:userId inMessage:cell.item.message.messageId dialog:_dialog];
        return;
    }
    /* a date is shown whole, in the words of the device, since the text over it is whatever the sender wrote */
    if ([url hasPrefix:@"noshigram-date:"]) {
        NSArray *parts = [[url substringFromIndex:[@"noshigram-date:" length]] componentsSeparatedByString:@":"];
        NSDate *moment = [NSDate dateWithTimeIntervalSince1970:[[parts objectAtIndex:0] doubleValue]];
        NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
        format.dateStyle = NSDateFormatterFullStyle;
        format.timeStyle = NSDateFormatterShortStyle;
        NoshiShowAlert(nil, [format stringFromDate:moment], [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
        return;
    }
    if ([url hasPrefix:@"noshigram-command:"]) {
        NSString *command = [url substringFromIndex:[@"noshigram-command:" length]];
        [self askFirst:NoshiChatFlagAskBotCommand message:[NSString stringWithFormat:NSLocalizedString(@"chat.ask.command", nil), command]
                action:NSLocalizedString(@"chat.ask.command.action", nil) then:^{ [((NoshiChatController *)weak.target)->_bots openLink:url]; } declined:nil];
        return;
    }
    /* the links that stay inside the app need no question; an address out in the web does */
    BOOL web = [url hasPrefix:@"http://"] || [url hasPrefix:@"https://"];
    NSRange host = [url rangeOfString:@"//t.me/"];
    NoshiLinkConfirm mode = NoshiChatLinkConfirm();
    BOOL ask = web && host.location == NSNotFound && (mode == NoshiLinkConfirmAlways || (mode == NoshiLinkConfirmHidden && [self isHiddenLink:url inMessage:cell.item.message]));
    if (!ask) {
        [_bots openLink:url];
        return;
    }
    NoshiShowAlert(nil, [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"chat.ask.link", nil), url],
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"chat.ask.link.action", nil), nil], 0, NO,
                     ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1) [((NoshiChatController *)weak.target)->_bots openLink:url];
    });
}

@end
