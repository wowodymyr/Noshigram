#import "noshi_emoji_label.h"
#import "noshi_dialog_cell.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_community_badge.h"
#import "noshi_lottie_view.h"
#import "noshi_pill_label.h"
#import "noshi_platform.h"
#import "noshi_chat_settings.h"
#import "noshi_draft.h"
#import "noshi_preview_thumb.h"
#import "noshi_status_label.h"
#import "noshi_story_ring.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_imported_theme.h"
#import "noshi_time.h"
#import "noshi_topic_icon.h"
#import "noshi_developers.h"
#import "noshi_custom_emoji.h"
#import "noshi_name_badge.h"

/* the interface scale of the chat settings: the row, the picture and the places of the lines in it grow with the fonts */
#define SCALED(v) ((v) * NoshiInterfaceScale())
#define MINI_SIDE 16.0
/* the compact density of the customization takes eight points off the row and six off the picture, and keeps the preview to one line */
static BOOL NoshiRowCompact(void) {
    return !NoshiThemeIsClassic() && NoshiListDensityStored() == 1;
}
#define ROW_HEIGHT (SCALED(64.0) - (NoshiRowCompact() ? SCALED(8.0) : 0))
#define AVATAR_SIZE (SCALED(48.0) - (NoshiRowCompact() ? SCALED(6.0) : 0))
#define RING_OUTSET 4.0
#define ONLINE_SIDE 14.0
#define ONLINE_BORDER 2.0
#define SIDE_MARGIN 14.0
#define BADGE_HEIGHT SCALED(18.0)
#define ICON_SIZE 11.0
#define FORWARD_SIDE 14.0
#define FORUM_TOPIC_ICON 15.0
/* a forum row stands taller: the name, a line of topics and the last message, each of the last two in a capsule */
#define FORUM_ROW_HEIGHT SCALED(86.0)
#define PILL_HEIGHT SCALED(24.0)
#define PILL_PAD 9.0
#define ACTION_WIDTH 80.0
#define ACTION_ICON_SIZE 32.0
/* a drag this far across the row, or a fast flick past half the button, performs the action without a tap */
#define COMMIT_FRACTION 0.6
#define COMMIT_FLICK 900.0
#define SETTLE_SECONDS 0.22

@interface NoshiDialogCell () <UIGestureRecognizerDelegate> {
    UIView *_slider;
    UIButton *_actionButton;
    UIView *_actionContent;
    UILabel *_actionLabel;
    NoshiLottieView *_actionIcon;
    UIPanGestureRecognizer *_pan;
    NSArray *_folderPaging;
    NoshiDialogAction _action;
    NoshiMediaCache *_media;
    CGFloat _offset;
    CGFloat _dragStart;
    BOOL _played;
    /* a settle or commit still running must not act on a row that was reused meanwhile */
    NSUInteger _generation;
    NoshiAvatarView *_avatar;
    NoshiStoryRing *_storyRing;
    /* the green dot on the corner of the avatar of a user who is on line */
    NoshiOnlineDotView *_onlineDot;
    /* the small picture of who wrote the last message of a group, when the setting asks for it */
    NoshiAvatarView *_mini;
    UIImageView *_topicIcon;
    /* a forum row names the topic of its last message between the name and the preview */
    UIImageView *_forumTopicIcon;
    NoshiEmojiLabel *_forumTopic;
    UIView *_topicPill;
    UIView *_messagePill;
    UIImageView *_pillChevron;
    UIImageView *_secondIcon;
    /* a folded community names its newest chats in the capsules with their pictures, where a forum has the icons of its topics */
    NoshiAvatarView *_capsuleAvatar;
    NoshiAvatarView *_capsuleSecondAvatar;
    BOOL _communityCapsules;
    NoshiEmojiLabel *_secondTopic;
    CGFloat _rowHeight;
    UIImageView *_communityBadge;
    UIButton *_communityHit;
    void (^_communityHandler)(void);
    NoshiEmojiLabel *_title;
    UIButton *_markHit;
    NSString *_markName;
    long long _markUserId;
    NSUInteger _marks;
    UIImageView *_mutedIcon;
    UILabel *_time;
    UIImageView *_checks;
    NoshiEmojiLabel *_preview;
    /* the words of what someone is typing, with the three dots before them; it lies over the preview while a chat is acted in */
    NoshiStatusLabel *_typing;
    NoshiPreviewThumb *_thumb;
    /* the arrow before the preview of a forwarded message */
    UIImageView *_forwardIcon;
    UILabel *_badge;
    UILabel *_mention;
    UILabel *_reaction;
    UIImageView *_pin;
    UIView *_line;
}
@end

@implementation NoshiDialogCell

@synthesize swipeDelegate = _swipeDelegate;
@synthesize media = _media;

- (void)markTapped:(UIControl *)control event:(UIEvent *)event {
    UITouch *touch = [[event touchesForView:control] anyObject];
    if (!touch) return;
    CGPoint point = [touch locationInView:_title];
    NSUInteger mark = NoshiMarkForDocument([_title customEmojiAtPoint:point]);
    if (mark) NoshiShowMarkNoticeForUser(_markName, mark, _markUserId);
}

+ (CGFloat)rowHeight {
    return ROW_HEIGHT;
}

static BOOL NoshiDialogShowsTopics(NoshiDialog *dialog) {
    return (dialog.forum || dialog.communityChats.count > 0) && dialog.forumTopicTitle.length > 0;
}

+ (CGFloat)rowHeightForDialog:(NoshiDialog *)dialog {
    return NoshiDialogShowsTopics(dialog) ? FORUM_ROW_HEIGHT : ROW_HEIGHT;
}

static NoshiEmojiLabel *NoshiCellEmojiLabel(UIFont *font, UIColor *color, NSInteger alignment) {
    NoshiEmojiLabel *label = [[[NoshiEmojiLabel alloc] init] autorelease];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

static UILabel *NoshiCellPill(UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[NoshiPillLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

static UILabel *NoshiCellLabel(UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

@synthesize communityHandler = _communityHandler;

- (void)communityTapped {
    if (_communityHandler) _communityHandler();
}

/* on the plate of a chosen row the green dot is white, with the ring in the color of the plate; elsewhere it is green on the ring of the screen */
- (void)refreshOnlineDot {
    BOOL chosen = self.selected || self.highlighted;
    _onlineDot.inverted = chosen;
    _onlineDot.layer.borderColor = (chosen ? NoshiColorField() : NoshiColorScreen()).CGColor;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self refreshOnlineDot];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self refreshOnlineDot];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = NoshiImportedThemeColor("chatList.itemHighlightedBg") ?: NoshiColorField();
    self.selectedBackgroundView = selected;

    /* the row slides inside the content view, which the cell resets to its own frame on every layout */
    _actionButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _actionButton.backgroundColor = NoshiColorAccent();
    _actionButton.clipsToBounds = YES;
    _actionButton.hidden = YES;
    [_actionButton addTarget:self action:@selector(commitSwipe) forControlEvents:UIControlEventTouchUpInside];
    _actionContent = [[UIView alloc] init];
    _actionContent.userInteractionEnabled = NO;
    [_actionButton addSubview:_actionContent];
    _actionLabel = [NoshiCellLabel(NoshiFontMedium(12), [UIColor whiteColor], NoshiTextAlignmentCenter) retain];
    [_actionContent addSubview:_actionLabel];
    [self.contentView addSubview:_actionButton];
    _slider = [[UIView alloc] init];
    _slider.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:_slider];
    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    _pan.delegate = self;
    [self addGestureRecognizer:_pan];

    _avatar = [[NoshiAvatarView alloc] init];
    [_slider addSubview:_avatar];
    _storyRing = [[NoshiStoryRing alloc] init];
    _storyRing.hidden = YES;
    _storyRing.followsAvatarShape = YES;
    [_slider addSubview:_storyRing];
    _onlineDot = [[NoshiOnlineDotView alloc] init];
    _onlineDot.hidden = YES;
    _onlineDot.userInteractionEnabled = NO;
    _onlineDot.layer.cornerRadius = ONLINE_SIDE / 2;
    _onlineDot.layer.borderWidth = ONLINE_BORDER;
    [_slider addSubview:_onlineDot];
    _mini = [[NoshiAvatarView alloc] init];
    _mini.circular = YES;
    _mini.hidden = YES;
    [_slider addSubview:_mini];
    _topicIcon = [[UIImageView alloc] init];
    _topicIcon.contentMode = UIViewContentModeScaleAspectFit;
    _topicIcon.hidden = YES;
    [_slider addSubview:_topicIcon];
    _rowHeight = ROW_HEIGHT;
    _topicPill = [[UIView alloc] init];
    _topicPill.layer.cornerRadius = PILL_HEIGHT / 2;
    _topicPill.hidden = YES;
    [_slider addSubview:_topicPill];
    _messagePill = [[UIView alloc] init];
    _messagePill.layer.cornerRadius = PILL_HEIGHT / 2;
    _messagePill.hidden = YES;
    [_slider addSubview:_messagePill];
    _pillChevron = [[UIImageView alloc] init];
    _pillChevron.hidden = YES;
    [_slider addSubview:_pillChevron];
    _secondIcon = [[UIImageView alloc] init];
    _secondIcon.contentMode = UIViewContentModeScaleAspectFit;
    _secondIcon.hidden = YES;
    [_slider addSubview:_secondIcon];
    _secondTopic = [NoshiCellEmojiLabel(NoshiFontRegular(14), NoshiColorSecondary(), NoshiTextAlignmentLeft) retain];
    _secondTopic.dropsUndrawable = YES;
    _secondTopic.hidden = YES;
    [_slider addSubview:_secondTopic];
    _forumTopicIcon = [[UIImageView alloc] init];
    _forumTopicIcon.contentMode = UIViewContentModeScaleAspectFit;
    _forumTopicIcon.hidden = YES;
    [_slider addSubview:_forumTopicIcon];
    _capsuleAvatar = [[NoshiAvatarView alloc] init];
    _capsuleAvatar.hidden = YES;
    [_slider addSubview:_capsuleAvatar];
    _capsuleSecondAvatar = [[NoshiAvatarView alloc] init];
    _capsuleSecondAvatar.hidden = YES;
    [_slider addSubview:_capsuleSecondAvatar];
    _forumTopic = [NoshiCellEmojiLabel(NoshiFontSemibold(14), NoshiColorAccent(), NoshiTextAlignmentLeft) retain];
    _forumTopic.dropsUndrawable = YES;
    _forumTopic.hidden = YES;
    [_slider addSubview:_forumTopic];
    _communityBadge = [[UIImageView alloc] initWithImage:NoshiCommunityBadgeImage()];
    _communityBadge.hidden = YES;
    [_slider addSubview:_communityBadge];
    _communityHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _communityHit.hidden = YES;
    [_communityHit addTarget:self action:@selector(communityTapped) forControlEvents:UIControlEventTouchUpInside];
    [_slider addSubview:_communityHit];
    _title = [NoshiCellEmojiLabel(NoshiFontSemibold(15.5), NoshiImportedThemeColor("chatList.title") ?: NoshiColorTitle(), NoshiTextAlignmentLeft) retain];
    _title.dropsUndrawable = YES;
    [_slider addSubview:_title];
    _markHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_markHit addTarget:self action:@selector(markTapped:event:) forControlEvents:UIControlEventTouchUpInside];
    [_slider addSubview:_markHit];
    _mutedIcon = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolBellSlash, 13, NoshiColorMuted())];
    [_slider addSubview:_mutedIcon];
    _time = [NoshiCellLabel(NoshiFontRegular(12.5), NoshiImportedThemeColor("chatList.dateText") ?: NoshiColorSecondary(), NoshiTextAlignmentRight) retain];
    [_slider addSubview:_time];
    _checks = [[UIImageView alloc] init];
    [_slider addSubview:_checks];
    _preview = [NoshiCellEmojiLabel(NoshiFontRegular(14), NoshiImportedThemeColor("chatList.messageText") ?: NoshiColorSecondary(), NoshiTextAlignmentLeft) retain];
    _preview.numberOfLines = 2;
    [_slider addSubview:_preview];
    _typing = [[NoshiStatusLabel alloc] init];
    _typing.backgroundColor = [UIColor clearColor];
    _typing.font = NoshiFontRegular(14);
    _typing.activeColor = NoshiColorAccent();
    _typing.hidden = YES;
    [_slider addSubview:_typing];
    _thumb = [[NoshiPreviewThumb alloc] init];
    [_slider addSubview:_thumb];
    _forwardIcon = [[UIImageView alloc] init];
    _forwardIcon.hidden = YES;
    [_slider addSubview:_forwardIcon];
    _badge = [NoshiCellPill(NoshiFontSemibold(11.5), [UIColor whiteColor], NoshiTextAlignmentCenter) retain];
    _badge.layer.cornerRadius = BADGE_HEIGHT / 2;
    /* a label's own background is not cut by the corner radius on its own, which left the count in a square */
    _badge.layer.masksToBounds = YES;
    [_slider addSubview:_badge];
    _mention = [NoshiCellPill(NoshiFontSemibold(11.5), [UIColor whiteColor], NoshiTextAlignmentCenter) retain];
    _mention.layer.cornerRadius = BADGE_HEIGHT / 2;
    _mention.layer.masksToBounds = YES;
    _mention.backgroundColor = NoshiColorAccent();
    /* the at sign is a picture set on the middle of the disc: the glyph of a font sits low and to the left in a label, whatever the alignment says */
    UIImageView *atMark = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolAt, 12, [UIColor whiteColor])] autorelease];
    atMark.center = CGPointMake(BADGE_HEIGHT / 2, BADGE_HEIGHT / 2);
    [_mention addSubview:atMark];
    [_slider addSubview:_mention];
    _reaction = [NoshiCellPill(NoshiFontSemibold(11.5), [UIColor whiteColor], NoshiTextAlignmentCenter) retain];
    _reaction.layer.cornerRadius = BADGE_HEIGHT / 2;
    _reaction.layer.masksToBounds = YES;
    _reaction.backgroundColor = [UIColor colorWithRed:230.0 / 255 green:62.0 / 255 blue:72.0 / 255 alpha:1];
    UIImageView *heartMark = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolHeart, 11, [UIColor whiteColor])] autorelease];
    heartMark.center = CGPointMake(BADGE_HEIGHT / 2, BADGE_HEIGHT / 2);
    [_reaction addSubview:heartMark];
    [_slider addSubview:_reaction];
    _pin = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolPin, 14, NoshiColorMuted())];
    [_slider addSubview:_pin];
    _line = [[UIView alloc] init];
    _line.backgroundColor = NoshiImportedThemeColor("chatList.itemSeparator") ?: NoshiColorHairline();
    [_slider addSubview:_line];
    return self;
}

- (void)dealloc {
    [_folderPaging release];
    _pan.delegate = nil;
    [_pan release];
    [_actionIcon release];
    [_actionLabel release];
    [_actionContent release];
    [_actionButton release];
    [_slider release];
    [_avatar release];
    [_storyRing release];
    [_onlineDot release];
    [_mini release];
    [_topicIcon release];
    [_forumTopicIcon release];
    [_capsuleAvatar release];
    [_capsuleSecondAvatar release];
    [_forumTopic release];
    [_topicPill release];
    [_messagePill release];
    [_pillChevron release];
    [_secondIcon release];
    [_secondTopic release];
    [_communityBadge release];
    [_communityHit release];
    [_communityHandler release];
    [_title release];
    [_markHit release];
    [_markName release];
    [_mutedIcon release];
    [_time release];
    [_checks release];
    [_preview release];
    [_typing release];
    [_thumb release];
    [_forwardIcon release];
    [_badge release];
    [_mention release];
    [_reaction release];
    [_pin release];
    [_line release];
    [super dealloc];
}

- (void)configureWithDialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars action:(NoshiDialogAction)action {
    ++_generation;
    _offset = 0;
    [self setSwipeAction:action];
    _avatar.seed = dialog.avatarSeed;
    _avatar.initials = dialog.initials;
    _avatar.deleted = dialog.deleted;
    _avatar.accent = dialog.saved || dialog.folder || dialog.replies;
    _avatar.symbol = dialog.folder ? NoshiSymbolArchive : (dialog.replies ? NoshiSymbolReply : NoshiSymbolBookmark);
    _avatar.showsSymbol = dialog.saved || dialog.folder || dialog.replies;
    [_avatar setPhoto:dialog.saved || dialog.folder || dialog.replies ? nil : dialog.photo cache:avatars];
    /* a topic has the icon of its own in the place of the group's photo */
    BOOL topic = dialog.topicId > 0;
    _avatar.hidden = topic;
    _topicIcon.hidden = !topic;
    _topicIcon.image = topic ? NoshiTopicIconImage(dialog) : nil;
    BOOL forumTopic = NoshiDialogShowsTopics(dialog);
    _rowHeight = forumTopic ? FORUM_ROW_HEIGHT : ROW_HEIGHT;
    _forumTopicIcon.hidden = _forumTopic.hidden = _topicPill.hidden = _messagePill.hidden = _pillChevron.hidden = !forumTopic;
    UIColor *pill = NoshiColorField();
    _topicPill.backgroundColor = pill;
    _messagePill.backgroundColor = pill;
    _pillChevron.image = forumTopic ? NoshiSymbolImage(NoshiSymbolChevronRight, 12, NoshiColorSecondary()) : nil;
    BOOL second = forumTopic && dialog.forumSecondTitle.length > 0;
    _secondIcon.hidden = _secondTopic.hidden = !second;
    _secondIcon.image = second ? NoshiTopicIconImageOf(dialog.forumSecondEmoji, dialog.forumSecondColor) : nil;
    _secondTopic.text = second ? dialog.forumSecondTitle : @"";
    _forumTopicIcon.image = forumTopic ? NoshiTopicIconImageOf(dialog.forumTopicEmoji, dialog.forumTopicColor) : nil;
    _forumTopic.text = forumTopic ? dialog.forumTopicTitle : @"";
    _forumTopic.textColor = NoshiColorAccent();
    _communityCapsules = forumTopic && dialog.communityChats.count > 0;
    if (_communityCapsules) {
        NoshiDialog *first = [dialog.communityChats objectAtIndex:0];
        _capsuleAvatar.seed = first.avatarSeed;
        _capsuleAvatar.initials = first.initials;
        [_capsuleAvatar setPhoto:first.photo cache:avatars];
        NoshiDialog *next = dialog.communityChats.count > 1 ? [dialog.communityChats objectAtIndex:1] : nil;
        _capsuleSecondAvatar.seed = next.avatarSeed;
        _capsuleSecondAvatar.initials = next.initials;
        [_capsuleSecondAvatar setPhoto:next.photo cache:avatars];
    } else {
        [_capsuleAvatar setPhoto:nil cache:nil];
        [_capsuleSecondAvatar setPhoto:nil cache:nil];
    }
    /* only a private chat with a live account has a presence; the saved messages row would show the own one */
    _onlineDot.hidden = topic || dialog.kind != NOSHI_DIALOG_USER || dialog.saved || dialog.presence != NOSHI_PRESENCE_ONLINE;
    [self refreshOnlineDot];
    _storyRing.hidden = YES;
    /* a chat that was added to a community wears the arrow of its avatar too, and the arrow opens the community */
    _communityBadge.hidden = !(dialog.community || dialog.linkedCommunityId);
    _communityHit.hidden = !dialog.linkedCommunityId;
    [_communityHandler release];
    _communityHandler = nil;
    NSArray *badge = nil;
    _marks = NoshiDialogIsDeveloper(dialog);
    [_markName release];
    _markName = [dialog.title copy];
    _markUserId = dialog.peerId;
    _title.text = NoshiNameWithBadges(dialog.title, NoshiDialogBadgeDocument(dialog), _marks, &badge);
    self.backgroundColor = NoshiImportedThemeColor(dialog.pinned ? "chatList.pinnedItemBg" : "chatList.itemBg") ?: [UIColor clearColor];
    self.selectedBackgroundView.backgroundColor = NoshiImportedThemeColor(dialog.pinned ? "chatList.pinnedItemHighlightedBg" : "chatList.itemHighlightedBg") ?: NoshiColorField();
    _title.entities = badge;
    _mutedIcon.hidden = !dialog.muted;
    _time.text = NoshiListTimeText(dialog.date);
    _preview.text = dialog.preview;
    _preview.entities = dialog.previewEntities;
    _preview.textColor = NoshiImportedThemeColor("chatList.messageText") ?: NoshiColorSecondary();
    /* the chats of the archive are mostly muted, so their grey badge hardly says that something is unread: the name goes bold and the preview takes the color of the name.
       the archive row of the list, which counts the unread chats inside it, is dressed the same */
    BOOL archivedUnread = dialog.folderId == 1 && (dialog.unreadCount > 0 || dialog.unread);
    _title.font = archivedUnread ? NoshiFontBold(15.5) : NoshiFontSemibold(15.5);
    _preview.font = archivedUnread ? NoshiFontSemibold(14) : NoshiFontRegular(14);
    if (archivedUnread) _preview.textColor = NoshiImportedThemeColor("chatList.title") ?: NoshiColorTitle();
    [_preview setPrefixLength:0 color:nil];
    _preview.hidden = NO;
    /* the capsule of a forum row has no room for the picture of the sender */
    BOOL mini = dialog.showsSender && !forumTopic && NoshiChatFlagGet(NoshiChatFlagSenderAvatars);
    _mini.hidden = !mini;
    if (mini) {
        _mini.seed = (NSUInteger)(dialog.senderId % 1000003);
        _mini.initials = dialog.senderInitials;
        [_mini setPhoto:dialog.senderPhoto cache:avatars];
    } else {
        [_mini setPhoto:nil cache:nil];
    }
    [_typing setStatus:@"" kind:NoshiStatusPlain];
    _typing.hidden = YES;
    [_thumb showFile:dialog.previewFile cache:_media];
    _forwardIcon.hidden = !dialog.forwarded;
    if (dialog.forwarded) _forwardIcon.image = NoshiSymbolImage(NoshiSymbolForward, FORWARD_SIDE, NoshiColorSecondary());
    if (dialog.outgoing && dialog.date > 0) {
        _checks.image = NoshiCheckImage(dialog.read, ICON_SIZE, NoshiImportedThemeColor("chatList.checkmark") ?: NoshiColorAccent());
        _checks.hidden = NO;
    } else {
        _checks.hidden = YES;
    }
    BOOL showsBadge = dialog.unreadCount > 0 || (dialog.unread && dialog.unreadCount == 0);
    _badge.hidden = !showsBadge;
    _badge.text = dialog.unreadCount > 999 ? @"999+" : (dialog.unreadCount > 0 ? [NSString stringWithFormat:@"%ld", (long)dialog.unreadCount] : @"");
    /* a chat with its notifications off counts in grey, as in the official clients, not in the accent that says something new is waiting; an imported theme may name its own */
    _badge.backgroundColor = NoshiImportedThemeColor(dialog.muted ? "chatList.unreadBadgeInactiveBg" : "chatList.unreadBadgeActiveBg") ?: (dialog.muted ? NoshiColorMuted() : NoshiColorAccent());
    _badge.textColor = NoshiImportedThemeColor(dialog.muted ? "chatList.unreadBadgeInactiveText" : "chatList.unreadBadgeActiveText") ?: [UIColor whiteColor];
    _mention.hidden = dialog.mentions <= 0;
    _reaction.hidden = dialog.reactions <= 0;
    _pin.hidden = !dialog.pinned || showsBadge || !_mention.hidden || !_reaction.hidden;
    self.accessibilityLabel = forumTopic ? [NSString stringWithFormat:@"%@, %@, %@", dialog.title, dialog.forumTopicTitle, dialog.preview]
                                         : [NSString stringWithFormat:@"%@, %@", dialog.title, dialog.preview];
    [self setNeedsLayout];
}

- (void)setStoryPeer:(NoshiStoryPeer *)peer {
    _storyRing.hidden = !peer || _avatar.hidden;
    if (peer) [_storyRing setPeer:peer];
    [self setNeedsLayout];
}

- (void)showDraft:(NoshiDraft *)draft {
    if (!draft) return;
    NSString *label = NSLocalizedString(@"chats.draft", nil);
    _preview.text = [NSString stringWithFormat:@"%@ %@", label, NoshiDraftPreviewText(draft)];
    _preview.entities = nil;
    [_preview setPrefixLength:label.length color:NoshiImportedThemeColor("chatList.messageDraftText") ?: NoshiColorBadgeRed()];
    _time.text = NoshiListTimeText(draft.date);
    _checks.hidden = YES;
    _mini.hidden = YES;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:_media];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", _title.text, _preview.text];
    [self setNeedsLayout];
}

- (void)showTypingText:(NSString *)text {
    if (!text) return;
    _typing.activeColor = NoshiColorAccent();
    [_typing setStatus:text kind:NoshiStatusTyping];
    _typing.hidden = NO;
    _preview.hidden = YES;
    _mini.hidden = YES;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:_media];
    [self setNeedsLayout];
}

#pragma mark swipe

static NSString *NoshiActionAnimation(NoshiDialogAction action) {
    switch (action) {
    case NoshiDialogActionArchive: return @"swipe_archive";
    case NoshiDialogActionUnarchive: return @"swipe_unarchive";
    case NoshiDialogActionHide: return @"swipe_hide";
    case NoshiDialogActionPin: return @"swipe_unhide";
    case NoshiDialogActionPinChat: return @"swipe_pin";
    case NoshiDialogActionUnpinChat: return @"swipe_unpin";
    case NoshiDialogActionMarkRead: return @"swipe_read";
    case NoshiDialogActionMarkUnread: return @"swipe_unread";
    case NoshiDialogActionMute: return @"swipe_mute";
    case NoshiDialogActionUnmute: return @"swipe_unmute";
    case NoshiDialogActionDeleteChat: return @"swipe_delete";
    case NoshiDialogActionNone: break;
    }
    return nil;
}

NoshiDialogAction NoshiDialogSwipeAction(NoshiDialog *dialog, NSInteger folderId) {
    if (folderId > 0) return NoshiChatFlagGet(NoshiChatFlagNoUnarchiveSwipe) ? NoshiDialogActionNone : NoshiDialogActionUnarchive;
    switch (NoshiChatSwipeStored()) {
    case NoshiChatSwipePin: return dialog.pinned ? NoshiDialogActionUnpinChat : NoshiDialogActionPinChat;
    case NoshiChatSwipeRead: return dialog.unread ? NoshiDialogActionMarkRead : NoshiDialogActionMarkUnread;
    case NoshiChatSwipeMute: return dialog.muted ? NoshiDialogActionUnmute : NoshiDialogActionMute;
    case NoshiChatSwipeDelete: return NoshiDialogActionDeleteChat;
    case NoshiChatSwipeFolders: return NoshiDialogActionNone;
    case NoshiChatSwipeArchive: break;
    }
    return dialog.saved ? NoshiDialogActionNone : NoshiDialogActionArchive;
}

NSString *NoshiDialogActionText(NoshiDialogAction action) {
    switch (action) {
    case NoshiDialogActionArchive: return NSLocalizedString(@"chats.archive.action", nil);
    case NoshiDialogActionUnarchive: return NSLocalizedString(@"chats.unarchive.action", nil);
    case NoshiDialogActionHide: return NSLocalizedString(@"chats.hide.action", nil);
    case NoshiDialogActionPin: return NSLocalizedString(@"chats.pin.action", nil);
    case NoshiDialogActionPinChat: return NSLocalizedString(@"chats.swipe.pin", nil);
    case NoshiDialogActionUnpinChat: return NSLocalizedString(@"chats.swipe.unpin", nil);
    case NoshiDialogActionMarkRead: return NSLocalizedString(@"chats.swipe.read", nil);
    case NoshiDialogActionMarkUnread: return NSLocalizedString(@"chats.swipe.unread", nil);
    case NoshiDialogActionMute: return NSLocalizedString(@"chats.swipe.mute", nil);
    case NoshiDialogActionUnmute: return NSLocalizedString(@"chats.swipe.unmute", nil);
    case NoshiDialogActionDeleteChat: return NSLocalizedString(@"chats.swipe.delete", nil);
    case NoshiDialogActionNone: break;
    }
    return @"";
}

- (void)setSwipeAction:(NoshiDialogAction)action {
    _action = action;
    _pan.enabled = action != NoshiDialogActionNone;
    _actionLabel.text = NoshiDialogActionText(action);
    /* deleting is the one swipe that is red; the others, the archive among them, take the accent of the app */
    _actionButton.backgroundColor = action == NoshiDialogActionDeleteChat ? [UIColor colorWithRed:0.89 green:0.31 blue:0.31 alpha:1] : NoshiColorAccent();
    [self releaseActionIcon];
    [self layoutSwipe];
}

/* the lottie document is parsed when a swipe starts, so a screenful of idle rows holds none */
- (void)prepareActionIcon {
    if (_actionIcon || _action == NoshiDialogActionNone) return;
    _actionIcon = [[NoshiLottieView alloc] initWithAnimationNamed:NoshiActionAnimation(_action)];
    [_actionContent addSubview:_actionIcon];
    _played = NO;
    [self layoutSwipe];
    [_actionIcon rewind];
}

- (void)releaseActionIcon {
    [_actionIcon removeFromSuperview];
    [_actionIcon release];
    _actionIcon = nil;
    _played = NO;
}

- (void)layoutSwipe {
    CGFloat width = self.contentView.bounds.size.width;
    _slider.frame = CGRectMake(-_offset, 0, width, _rowHeight);
    _actionButton.hidden = _offset <= 0;
    _actionButton.frame = CGRectMake(width - _offset, 0, _offset, _rowHeight);
    /* the icon keeps to the moving edge until the button is wide enough to center it */
    CGFloat slot = MAX(_offset, ACTION_WIDTH);
    _actionContent.frame = CGRectMake(0, 0, slot, _rowHeight);
    _actionIcon.frame = CGRectMake((slot - ACTION_ICON_SIZE) / 2, 9, ACTION_ICON_SIZE, ACTION_ICON_SIZE);
    _actionLabel.frame = CGRectMake(0, 43, slot, 15);
}

- (BOOL)swipeOpen {
    return _offset > 0;
}

- (void)moveSwipeTo:(CGFloat)offset animated:(BOOL)animated completion:(void (^)(void))completion {
    void (^change)(void) = ^{
        _offset = offset;
        [self layoutSwipe];
    };
    if (!animated) {
        change();
        if (completion) completion();
        return;
    }
    NSUInteger generation = _generation;
    [UIView animateWithDuration:SETTLE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:change
                     completion:^(BOOL finished) {
        (void)finished;
        if (generation == _generation && completion) completion();
    }];
}

- (void)closeSwipeAnimated:(BOOL)animated {
    if (_offset <= 0) return;
    /* the settle can end after the next drag began (the animation of an ipad is cut short by the first move of the new drag), and the icon of that drag would go with it;
       only a row that is closed and not being dragged lets it go */
    [self moveSwipeTo:0 animated:animated completion:^{
        BOOL dragging = _pan.state == UIGestureRecognizerStateBegan || _pan.state == UIGestureRecognizerStateChanged;
        if (_offset <= 0 && !dragging) [self releaseActionIcon];
    }];
}

- (void)commitSwipe {
    if (_action == NoshiDialogActionNone) return;
    NoshiDialogAction action = _action;
    NSUInteger generation = _generation;
    [self prepareActionIcon];
    if (!_played) {
        _played = YES;
        [_actionIcon playOnce];
    }
    [self moveSwipeTo:self.contentView.bounds.size.width animated:YES completion:^{
        if (generation == _generation) [_swipeDelegate dialogCell:self didTriggerAction:action];
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != _pan) return YES;
    CGPoint velocity = [_pan velocityInView:self];
    if (fabs(velocity.x) <= fabs(velocity.y)) return NO;
    return velocity.x < 0 || _offset > 0;
}

- (void)yieldSwipeToRecognizers:(NSArray *)recognizers {
    if (recognizers == _folderPaging) return;
    [_folderPaging release];
    _folderPaging = [recognizers copy];
    for (UIGestureRecognizer *recognizer in _folderPaging) [_pan requireGestureRecognizerToFail:recognizer];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGFloat width = self.contentView.bounds.size.width;
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
        _dragStart = _offset;
        [_swipeDelegate dialogCellDidBeginSwipe:self];
        [self prepareActionIcon];
        break;
    case UIGestureRecognizerStateChanged: {
        _offset = MIN(width, MAX(0, _dragStart - [pan translationInView:self].x));
        [self prepareActionIcon];
        [self layoutSwipe];
        if (!_played && _offset >= ACTION_WIDTH * 0.9) {
            _played = YES;
            [_actionIcon playOnce];
        }
        break;
    }
    case UIGestureRecognizerStateEnded: {
        CGFloat velocity = [pan velocityInView:self].x;
        if (_offset >= width * COMMIT_FRACTION || (velocity < -COMMIT_FLICK && _offset >= ACTION_WIDTH / 2)) {
            [self commitSwipe];
        } else if (_offset >= ACTION_WIDTH / 2 && velocity < COMMIT_FLICK) {
            [self moveSwipeTo:ACTION_WIDTH animated:YES completion:NULL];
        } else {
            [self closeSwipeAnimated:YES];
        }
        break;
    }
    default:
        [self closeSwipeAnimated:YES];
        break;
    }
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textX = SIDE_MARGIN * 2 + 2 + AVATAR_SIZE - 2;
    CGFloat hairline = 1.0 / NoshiScreenScale();
    _avatar.frame = CGRectMake(SIDE_MARGIN, _rowHeight > ROW_HEIGHT ? SCALED(10) : (ROW_HEIGHT - AVATAR_SIZE) / 2, AVATAR_SIZE, AVATAR_SIZE);
    _topicIcon.frame = _avatar.frame;
    _storyRing.frame = CGRectInset(_avatar.frame, -RING_OUTSET, -RING_OUTSET);
    _onlineDot.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - ONLINE_SIDE + 1, CGRectGetMaxY(_avatar.frame) - ONLINE_SIDE + 1, ONLINE_SIDE, ONLINE_SIDE);
    _communityBadge.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - NOSHI_COMMUNITY_BADGE_SIDE + 2, CGRectGetMaxY(_avatar.frame) - NOSHI_COMMUNITY_BADGE_SIDE + 2,
                                       NOSHI_COMMUNITY_BADGE_SIDE, NOSHI_COMMUNITY_BADGE_SIDE);
    _communityHit.frame = CGRectInset(_communityBadge.frame, -10, -10);

    CGSize badgeSize = CGSizeZero;
    CGFloat trailing = 0;
    if (!_badge.hidden) {
        CGSize fit = [_badge sizeThatFits:CGSizeMake(80, BADGE_HEIGHT)];
        badgeSize.width = _badge.text.length ? MAX(BADGE_HEIGHT, fit.width + 12) : 10;
        badgeSize.height = _badge.text.length ? BADGE_HEIGHT : 10;
        trailing = badgeSize.width + 8;
    } else if (!_pin.hidden) {
        trailing = _pin.image.size.width + 8;
    }
    /* a chat that mentions the person marks it with an @ next to the count */
    if (!_mention.hidden) trailing += BADGE_HEIGHT + (trailing ? 4 : 8);
    /* a reaction we have not seen gets a red disc with a heart, left of the @ */
    if (!_reaction.hidden) trailing += BADGE_HEIGHT + (trailing ? 4 : 8);
    /* a preview that wraps pulls the nick up and leaves a wider gap under it; a one line preview sits close under the nick */
    CGFloat thumbRoom = _thumb.hidden ? 0 : [NoshiPreviewThumb room];
    /* the small picture of the sender stands first in the line, and what follows it moves over */
    CGFloat miniRoom = _mini.hidden ? 0 : MINI_SIDE + 5;
    thumbRoom += miniRoom;
    /* the arrow of a forward comes before the picture and the words, so they move over by its width */
    CGFloat forwardRoom = _forwardIcon.hidden ? 0 : FORWARD_SIDE + 4;
    thumbRoom += forwardRoom;
    /* the two line row of the chat settings keeps the preview to one line; the three line row lets it take a second */
    /* the topic line takes the second line of the row, so the preview keeps to one line under it */
    BOOL topicLine = !_forumTopic.hidden;
    BOOL singleLine = topicLine || NoshiRowCompact() || NoshiChatListStyleStored() == NoshiChatListTwoLines;
    _preview.numberOfLines = singleLine ? 1 : 2;
    /* the last message of a forum sits in a capsule that has a chevron at its end, so the words start and stop inside it */
    CGFloat previewX = topicLine ? textX + PILL_PAD : textX;
    CGFloat chevronRoom = topicLine ? PILL_PAD + 12 + 4 : 0;
    CGSize previewSize = [_preview sizeThatFits:CGSizeMake(MAX(0, width - SIDE_MARGIN - previewX - trailing - thumbRoom - chevronRoom), 40)];
    BOOL wraps = !singleLine && previewSize.height > _preview.font.lineHeight * 1.5;
    CGFloat topicY = SCALED(33), pillY = SCALED(33) + PILL_HEIGHT + 2;
    /* the lines of a compact row stand half of what the row lost higher, which keeps them in its middle */
    CGFloat lift = topicLine || !NoshiRowCompact() ? 0 : SCALED(4);
    CGFloat titleY = topicLine ? SCALED(8) : (wraps ? SCALED(6) : SCALED(12) - lift);
    CGFloat previewY = topicLine ? pillY + (PILL_HEIGHT - ceil(_preview.font.lineHeight) - 1) / 2 : (wraps ? SCALED(31) : SCALED(33) - lift);
    CGFloat previewHeight = wraps ? SCALED(34) : ceil(_preview.font.lineHeight) + 1;

    CGSize timeSize = [_time sizeThatFits:CGSizeMake(120, SCALED(20))];
    CGFloat timeX = width - SIDE_MARGIN - timeSize.width;
    _time.frame = CGRectMake(timeX, titleY + 1, timeSize.width, SCALED(18));
    CGFloat titleRight = timeX - 6;
    if (!_checks.hidden) {
        CGSize checkSize = _checks.image.size;
        CGFloat checkX = timeX - 4 - checkSize.width;
        _checks.frame = CGRectMake(checkX, titleY + 1 + (SCALED(18) - checkSize.height) / 2, checkSize.width, checkSize.height);
        titleRight = checkX - 6;
    }
    CGFloat iconSpace = _mutedIcon.hidden ? 0 : _mutedIcon.image.size.width + 4;
    CGFloat titleMax = MAX(0, titleRight - textX - iconSpace);
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(titleMax, SCALED(20))];
    CGFloat titleWidth = MIN(titleSize.width, titleMax);
    _title.frame = CGRectMake(textX, titleY, titleWidth, SCALED(20));
    CGFloat fullTitleWidth = [_title sizeThatFits:CGSizeMake(4096, 20)].width;
    NSUInteger markCount = 0;
    for (NSUInteger bit = 1; bit <= NoshiMarkFlawSeer; bit <<= 1) if (_marks & bit) ++markCount;
    CGFloat markWidth = markCount * 30.0;
    _markHit.hidden = !markCount || fullTitleWidth > titleMax;
    _markHit.frame = CGRectMake(textX + MAX(0, titleWidth - markWidth), titleY - 4, MIN(titleWidth, markWidth), 28);
    _mutedIcon.frame = CGRectMake(textX + titleWidth + 4, titleY + (SCALED(20) - _mutedIcon.image.size.height) / 2,
                                  _mutedIcon.image.size.width, _mutedIcon.image.size.height);

    /* the topic of the last message stands in a capsule, and the topic before it follows in plain words as far as the row reaches */
    CGFloat topicHeight = ceil(_forumTopic.font.lineHeight) + 1;
    CGFloat rowRight = width - SIDE_MARGIN;
    CGFloat nameX = textX + PILL_PAD + FORUM_TOPIC_ICON + 4;
    CGFloat nameWidth = MIN([_forumTopic sizeThatFits:CGSizeMake(4096, topicHeight)].width, MAX(0, rowRight - PILL_PAD - nameX));
    CGFloat pillRight = nameX + nameWidth + PILL_PAD;
    _topicPill.frame = CGRectMake(textX, topicY, pillRight - textX, PILL_HEIGHT);
    _forumTopicIcon.frame = CGRectMake(textX + PILL_PAD, topicY + (PILL_HEIGHT - FORUM_TOPIC_ICON) / 2, FORUM_TOPIC_ICON, FORUM_TOPIC_ICON);
    _forumTopic.frame = CGRectMake(nameX, topicY + (PILL_HEIGHT - topicHeight) / 2, nameWidth, topicHeight);
    CGFloat secondX = pillRight + 8;
    CGFloat secondNameX = secondX + FORUM_TOPIC_ICON + 4;
    BOOL secondFits = !_secondTopic.hidden && rowRight - secondNameX >= 36;
    _secondIcon.hidden = _secondTopic.hidden ? YES : !secondFits;
    _secondIcon.frame = CGRectMake(secondX, topicY + (PILL_HEIGHT - FORUM_TOPIC_ICON) / 2, FORUM_TOPIC_ICON, FORUM_TOPIC_ICON);
    /* the pictures of the chats take the places of the icons of the topics */
    BOOL secondPicture = _communityCapsules && !_secondIcon.hidden;
    _capsuleAvatar.hidden = !_communityCapsules;
    _capsuleAvatar.frame = _forumTopicIcon.frame;
    _capsuleSecondAvatar.hidden = !secondPicture;
    _capsuleSecondAvatar.frame = _secondIcon.frame;
    if (_communityCapsules) _forumTopicIcon.hidden = _secondIcon.hidden = YES;
    _secondTopic.frame = CGRectMake(secondNameX, topicY + (PILL_HEIGHT - topicHeight) / 2, MAX(0, rowRight - secondNameX), topicHeight);
    CGFloat messageRight = width - SIDE_MARGIN - trailing;
    _messagePill.frame = CGRectMake(textX, pillY, MAX(0, messageRight - textX), PILL_HEIGHT);
    _pillChevron.frame = CGRectMake(messageRight - PILL_PAD - 12, pillY + (PILL_HEIGHT - 12) / 2, 12, 12);

    CGFloat markCenter = topicLine ? pillY + PILL_HEIGHT / 2 : previewY + (wraps ? SCALED(16) : SCALED(9));
    CGFloat badgesRight = width - SIDE_MARGIN - (_badge.hidden ? 0 : badgeSize.width + 4);
    if (!_mention.hidden) {
        _mention.frame = CGRectMake(badgesRight - BADGE_HEIGHT, markCenter - BADGE_HEIGHT / 2, BADGE_HEIGHT, BADGE_HEIGHT);
        badgesRight -= BADGE_HEIGHT + 4;
    }
    if (!_reaction.hidden) _reaction.frame = CGRectMake(badgesRight - BADGE_HEIGHT, markCenter - BADGE_HEIGHT / 2, BADGE_HEIGHT, BADGE_HEIGHT);
    if (!_badge.hidden) {
        _badge.layer.cornerRadius = badgeSize.height / 2;
        _badge.frame = CGRectMake(width - SIDE_MARGIN - badgeSize.width, markCenter - badgeSize.height / 2, badgeSize.width, badgeSize.height);
    } else if (!_pin.hidden) {
        CGSize pinSize = _pin.image.size;
        _pin.frame = CGRectMake(width - SIDE_MARGIN - pinSize.width, markCenter - pinSize.height / 2, pinSize.width, pinSize.height);
    }
    _preview.frame = CGRectMake(previewX + thumbRoom, previewY, MAX(0, width - SIDE_MARGIN - previewX - trailing - thumbRoom - chevronRoom), previewHeight);
    _typing.frame = CGRectMake(previewX, previewY, MAX(0, width - SIDE_MARGIN - previewX - trailing - chevronRoom), ceil(_preview.font.lineHeight) + 1);
    _forwardIcon.frame = CGRectMake(previewX + miniRoom, previewY + (ceil(_preview.font.lineHeight) + 1 - FORWARD_SIDE) / 2, FORWARD_SIDE, FORWARD_SIDE);
    _thumb.frame = CGRectMake(previewX + miniRoom + forwardRoom, previewY + (ceil(_preview.font.lineHeight) + 1 - [NoshiPreviewThumb side]) / 2, [NoshiPreviewThumb side], [NoshiPreviewThumb side]);
    _mini.frame = CGRectMake(previewX, previewY + (ceil(_preview.font.lineHeight) + 1 - MINI_SIDE) / 2, MINI_SIDE, MINI_SIDE);
    _line.frame = CGRectMake(textX, _rowHeight - hairline, width - textX, hairline);
    [self layoutSwipe];
}

@end
