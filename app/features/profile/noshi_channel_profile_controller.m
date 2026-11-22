#import "noshi_platform.h"
#import "noshi_avatar_viewer.h"
#import "noshi_profile_hero_view.h"
#import "noshi_channel_profile_controller.h"
#import "noshi_notifications_chat_controller.h"
#import "noshi_media_viewer.h"
#import "noshi_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_story.h"
#import "noshi_story_ring.h"
#import "noshi_story_viewer_controller.h"
#import "noshi_avatar_viewer.h"
#import "noshi_channel_errors.h"
#import "noshi_chat_controller.h"
#import "noshi_community_screen.h"
#import "noshi_contact_picker_controller.h"
#import "noshi_emoji_label.h"
#import "noshi_channel_manage_controller.h"
#import "noshi_gift_detail_controller.h"
#import "noshi_gift_facts_view.h"
#import "noshi_gift_grid_view.h"
#import "noshi_group_tabs_view.h"
#import "noshi_user_profile_controller.h"
#import "noshi_info_card_view.h"
#import "noshi_popup_menu.h"
#import "noshi_profile_action.h"
#import "noshi_profile_chat.h"
#import "noshi_profile_qr_controller.h"
#import "noshi_profile_feed.h"
#import "noshi_report_flow.h"
#import "noshi_sheet.h"
#import "noshi_session_channels.h"
#import "noshi_star_gift.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_plural.h"
#import "noshi_topic_icon.h"
#import "noshi_info_rows.h"

/* the group info of telegram for ios 4: a white head of 97 points with the photo of 66 at the left and the name and the count of members beside it, then white groups of rows */
#define AVATAR 66.0
#define HEAD_HEIGHT 97.0
#define NAME_X 92.0
#define GAP NOSHI_INFO_SECTION_GAP
#define LINKED_HEIGHT 64.0

/* a linked group as a card: its picture, its name and a line that says what it is, with a chevron */
@interface NoshiLinkedGroupCard : UIControl {
    NoshiAvatarView *_picture;
    NoshiEmojiLabel *_title;
    UILabel *_caption;
    UIImageView *_chevron;
}
- (void)configureWithDialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars;
/* the line under the name */
- (void)setCaption:(NSString *)caption;
@end

@implementation NoshiLinkedGroupCard

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = NoshiColorCard();
    _picture = [[NoshiAvatarView alloc] init];
    [self addSubview:_picture];
    _title = [[NoshiEmojiLabel alloc] init];
    _title.dropsUndrawable = YES;
    _title.textColor = NoshiColorTitle();
    _title.font = NoshiFontSemibold(17);
    [self addSubview:_title];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textColor = NoshiColorSecondary();
    _caption.font = NoshiFontRegular(14);
    [self addSubview:_caption];
    _chevron = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolChevronRight, 13, [UIColor colorWithRed:0.78 green:0.78 blue:0.8 alpha:1])];
    _chevron.contentMode = UIViewContentModeCenter;
    [self addSubview:_chevron];
    for (UIView *view in self.subviews) view.userInteractionEnabled = NO;
    return self;
}

- (void)dealloc {
    [_picture release];
    [_title release];
    [_caption release];
    [_chevron release];
    [super dealloc];
}

- (void)setCaption:(NSString *)caption {
    _caption.text = caption;
}

- (void)configureWithDialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars {
    _picture.initials = dialog.initials;
    _picture.seed = dialog.avatarSeed;
    [_picture setPhoto:dialog.photo cache:avatars];
    _title.text = dialog.title;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _picture.frame = CGRectMake(15, (size.height - 44) / 2, 44, 44);
    _title.frame = CGRectMake(71, 10, size.width - 71 - 40, 22);
    _caption.frame = CGRectMake(71, 34, size.width - 71 - 40, 20);
    _chevron.frame = CGRectMake(size.width - 34, 0, 24, size.height);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? (NoshiThemeIsDark() ? [UIColor colorWithWhite:0.25 alpha:1] : [UIColor colorWithWhite:0.85 alpha:1]) : NoshiColorCard();
}

@end

@interface NoshiChannelProfileController () <NoshiGiftGridDelegate, NoshiGroupTabsDelegate> {
    NoshiDialog *_dialog;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;
    NoshiGiftGridView *_grid;
    UIView *_head;
    NoshiAvatarView *_avatar;
    /* the profile of a forum topic shows the icon of the topic where a group shows its photo, and counts messages where a group counts nothing */
    UIImageView *_topicIcon;
    NSInteger _topicMessages;
    BOOL _topicMessagesKnown;
    /* getFullChannel fails now and then on a bad network, and nothing else fills the sections under the head, so it is asked again a few times */
    NSUInteger _fullAttempts;
    NoshiProfileHeroView *_hero;
    /* the photo opened wide in the head: the frame it was a circle in, the height it grows to, and whether it is open */
    CGRect _heroCircle;
    CGFloat _heroHeight;
    BOOL _heroOpen;
    /* the list runs under the bar while the wide photo is open, so the photo can reach the top of the screen */
    BOOL _heroUnderBar;
    BOOL _heroMoving;
    BOOL _viewerWanted;
    NoshiStoryRing *_storyRing;
    NoshiStoryPeer *_storyPeer;
    BOOL _storiesShown;
    NoshiEmojiLabel *_name;
    UILabel *_status;
    /* the white ground of the head and the groups of rows under the information */
    UIView *_headPanel;
    UIView *_actionsGroup;
    NoshiInfoRow *_joinRow;
    NoshiInfoRow *_messageRow;
    NoshiInfoRow *_addRow;
    NoshiInfoRow *_linkRow;
    UIView *_soundGroup;
    NoshiInfoRow *_soundRow;
    UIView *_countsGroup;
    NoshiInfoRow *_membersRow;
    NoshiInfoRow *_adminsRow;
    NoshiInfoRow *_bannedRow;
    NoshiInfoCardView *_info;
    /* the community the channel was added to */
    NoshiLinkedGroupCard *_communityCard;
    NoshiDialog *_community;
    /* the bottom hairline of the community row, which stands alone as a group */
    UIView *_communityLine;
    NoshiGroupTabsView *_groupTabs;
    UILabel *_giftsTitle;
    UILabel *_empty;
    UILabel *_toast;
    NoshiProfileFeed *_feed;
    NoshiFullChannel *_full;
    BOOL _muteBusy;
    BOOL _joinBusy;
    BOOL _joined;
    CGFloat _headHeight;
    CGFloat _headWidth;
}
@end

@implementation NoshiChannelProfileController

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _stickers = [stickers retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _feed = [[NoshiProfileFeed alloc] initWithSession:session kind:NoshiFeedGifts owner:dialog];
    /* the bar says Info, as it did in telegram for ios 4; the name is in the head under it */
    self.screenTitle = NSLocalizedString(@"profile.row.info", nil);
    return self;
}

/* the ring round the picture follows the stories of the channel, as on the profile of a person */
- (void)loadStories {
    NoshiWeakReference *me = _weak;
    [self retain];
    [self.session loadStoriesOfDialog:_dialog completion:^(NoshiStoryPeer *peer, NSArray *stories, NSString *errorName) {
        [self autorelease];
        NoshiChannelProfileController *profile = me.target;
        if (!profile || errorName) return;
        [profile->_storyPeer release];
        profile->_storyPeer = stories.count ? [peer retain] : nil;
        profile->_storyRing.hidden = !profile->_storyPeer;
        if (profile->_storyPeer) [profile->_storyRing setPeer:profile->_storyPeer];
        [profile.view setNeedsLayout];
    }];
}

- (void)avatarTapped {
    if (!_storyPeer) {
        [self openHero];
        return;
    }
    /* a second tap while a viewer is up or rising would stack another viewer on the first, and both would play the same story's sound */
    if (self.presentedViewController) return;
    NoshiStoryViewerController *viewer = [[[NoshiStoryViewerController alloc] initWithSession:self.session peers:[NSArray arrayWithObject:_storyPeer] index:0
                                                                                          avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_storiesShown) [self loadStories];
    _storiesShown = YES;
}

/* a tap on the photo opens it wide inside the head, as the profile of a person does; the cards ride up over its lower edge and the rest of the head moves down */
- (void)openHero {
    if (_hero || _heroMoving) return;
    /* with no photo there is nothing to open wide, and the viewer would be a black screen */
    if (!_dialog.photo) return;
    NoshiProfileHeroView *hero = [[[NoshiProfileHeroView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media] autorelease];
    hero.name.text = _name.text;
    hero.name.entities = _name.entities;
    hero.status.text = _status.text;
    _heroCircle = _avatar.frame;
    _heroHeight = [NoshiProfileHeroView heightForWidth:_grid.bounds.size.width screenHeight:self.view.bounds.size.height];
    hero.frame = _heroCircle;
    hero.stripTop = NoshiLayoutInsets(self).top + 8;
    hero.layer.cornerRadius = _heroCircle.size.width / 2;
    [hero beginMove];
    _heroUnderBar = YES;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [_head insertSubview:hero aboveSubview:_avatar];
    _hero = [hero retain];
    _heroOpen = YES;
    _heroMoving = YES;
    BOOL motion = !NoshiReduceMotionEnabled();
    [hero animateCornerTo:0 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _name.alpha = 0;
        _status.alpha = 0;
        [self setBarOverPhoto:YES];
        [self layoutHead];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        _avatar.hidden = YES;
        [_hero finishOpen];
        if (_viewerWanted) {
            _viewerWanted = NO;
            [self openAvatarViewer];
        }
    }];
}

/* the photos on the whole screen; the arrow of the viewer comes back to the wide photo, which stays open under it */
/* a long pull goes through the whole opening of the wide photo in one drag: the part that came while it opened is kept, or the photos would ask for a second pull */
- (BOOL)holdsPullWhileOpening:(CGFloat)pull {
    if (!_heroMoving) return NO;
    if (_heroOpen && pull > 130) _viewerWanted = YES;
    return YES;
}

/* the screen's own swipes: a pull down opens the photo wide, a longer one opens the photos, and scrolling up closes the wide photo */
- (void)heroFollowsPull:(CGFloat)pull {
    if ([self holdsPullWhileOpening:pull]) return;
    if (!_hero) {
        if (pull > 60) [self openHero];
    } else if (_heroOpen) {
        if (pull > 130) [self openAvatarViewer];
        else if (-pull > 90) [self closeHero];
    }
}

- (void)openAvatarViewer {
    if (!_hero || !_heroOpen || _heroMoving || self.presentedViewController) return;
    NoshiAvatarViewer *viewer = [[[NoshiAvatarViewer alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media] autorelease];
    viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)closeHero {
    if (!_hero || !_heroOpen || _heroMoving) return;
    _heroMoving = YES;
    _heroOpen = NO;
    _avatar.hidden = NO;
    [_hero beginClose];
    BOOL motion = !NoshiReduceMotionEnabled();
    [_hero animateCornerTo:_heroCircle.size.width / 2 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _name.alpha = 1;
        _status.alpha = 1;
        [self setBarOverPhoto:NO];
        [self layoutHead];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        [_hero removeFromSuperview];
        [_hero release];
        _hero = nil;
        _heroUnderBar = NO;
        [self.view setNeedsLayout];
    }];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_dialog release];
    [_stickers release];
    [_grid release];
    [_hero release];
    [_head release];
    [_avatar release];
    [_topicIcon release];
    [_storyRing release];
    [_storyPeer release];
    [_name release];
    [_status release];
    [_headPanel release];
    [_actionsGroup release];
    [_joinRow release];
    [_messageRow release];
    [_addRow release];
    [_linkRow release];
    [_soundGroup release];
    [_soundRow release];
    [_countsGroup release];
    [_membersRow release];
    [_adminsRow release];
    [_bannedRow release];
    [_info release];
    [_communityCard release];
    [_community release];
    [_communityLine release];
    _groupTabs.delegate = nil;
    [_groupTabs release];
    [_giftsTitle release];
    [_empty release];
    [_toast release];
    [_feed release];
    [_full release];
    [super dealloc];
}

static UILabel *NoshiChannelProfileLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[NoshiGiftGridView alloc] initWithMedia:self.media];
    _grid.avatars = self.avatars;
    _grid.delegate = self;
    [root addSubview:_grid];

    _head = [[UIView alloc] init];
    _head.backgroundColor = [UIColor clearColor];
    _headPanel = NoshiNewInfoGroup();
    [_head addSubview:_headPanel];
    _storyRing = [[NoshiStoryRing alloc] init];
    _storyRing.hidden = YES;
    [_head addSubview:_storyRing];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.seed = _dialog.avatarSeed;
    _avatar.initials = _dialog.initials;
    [_avatar setPhoto:_dialog.photo cache:self.avatars];
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)] autorelease]];
    [_head addSubview:_avatar];
    if ([self isTopic]) {
        _avatar.hidden = YES;
        _topicIcon = [[UIImageView alloc] init];
        _topicIcon.contentMode = UIViewContentModeScaleAspectFit;
        _topicIcon.image = NoshiTopicIconImage(_dialog);
        [_head addSubview:_topicIcon];
    }
    _name = [[NoshiEmojiLabel alloc] init];
    _name.dropsUndrawable = YES;
    _name.textColor = NoshiColorTitle();
    _name.textAlignment = NoshiTextAlignmentLeft;
    _name.numberOfLines = 2;
    _name.text = _dialog.title;
    [_head addSubview:_name];
    _status = NoshiChannelProfileLabel(NoshiColorSecondary(), [UIFont systemFontOfSize:15], NoshiTextAlignmentLeft);
    _status.text = [self kindText];
    [_head addSubview:_status];

    /* the actions of the group info of telegram for ios 4 are rows of words in the accent */
    _actionsGroup = NoshiNewInfoGroup();
    _joinRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(_dialog.kind == NOSHI_DIALOG_GROUP ? @"group.row.join" : @"channel.row.join", nil) accent:YES chevron:NO target:self action:@selector(join)];
    _messageRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.message", nil) accent:YES chevron:NO target:self action:@selector(openMessages)];
    _addRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"group.row.add", nil) accent:YES chevron:NO target:self action:@selector(addMembers)];
    /* the link is copied, because the share sheet starts at ios 6 */
    _linkRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.qr.copy", nil) accent:YES chevron:NO target:self action:@selector(copyLink)];
    for (NoshiInfoRow *row in [NSArray arrayWithObjects:_joinRow, _messageRow, _addRow, _linkRow, nil]) [_actionsGroup addSubview:row];
    [_head addSubview:_actionsGroup];
    _soundGroup = NoshiNewInfoGroup();
    _soundRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.notifications", nil) accent:NO chevron:NO target:self action:@selector(toggleMute)];
    [_soundGroup addSubview:_soundRow];
    [_head addSubview:_soundGroup];
    /* the counts are rows with the number in grey at the right */
    _countsGroup = NoshiNewInfoGroup();
    _membersRow = [[NoshiInfoRow alloc] initWithTitle:@"" accent:NO chevron:NO target:nil action:NULL];
    _adminsRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"channel.admins", nil) accent:NO chevron:NO target:nil action:NULL];
    _bannedRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"channel.banned", nil) accent:NO chevron:NO target:nil action:NULL];
    for (NoshiInfoRow *row in [NSArray arrayWithObjects:_membersRow, _adminsRow, _bannedRow, nil]) [_countsGroup addSubview:row];
    [_head addSubview:_countsGroup];

    _info = [[NoshiInfoCardView alloc] init];
    NoshiWeakReference *me = _weak;
    _info.copyHandler = ^{ [(NoshiChannelProfileController *)me.target toast:NSLocalizedString(@"profile.copied", nil)]; };
    /* the code of the link is a button at the right end of the link row, as on a profile, and the row only exists when there is a link to show */
    _info.codeCaption = NSLocalizedString(@"channel.link", nil);
    _info.codeHandler = ^{ [(NoshiChannelProfileController *)me.target openQr]; };
    [_head addSubview:_info];
    _communityCard = [[NoshiLinkedGroupCard alloc] init];
    [_communityCard setCaption:NSLocalizedString(@"channel.community.card", nil)];
    _communityCard.hidden = YES;
    [_communityCard addTarget:self action:@selector(openCommunity) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_communityCard];
    _communityLine = [[UIView alloc] init];
    _communityLine.backgroundColor = NoshiInfoLineColor();
    [_communityCard addSubview:_communityLine];
    _giftsTitle = NoshiChannelProfileLabel(NoshiColorAccent(), NoshiFontSemibold(15), NoshiTextAlignmentLeft);
    _giftsTitle.text = NSLocalizedString(@"gifts.title", nil);
    _giftsTitle.hidden = YES;
    [_head addSubview:_giftsTitle];
    _empty = NoshiChannelProfileLabel(NoshiColorSecondary(), NoshiFontRegular(15), NoshiTextAlignmentCenter);
    _empty.numberOfLines = 0;
    [_head addSubview:_empty];
    _grid.headerView = _head;

    _toast = NoshiChannelProfileLabel([UIColor whiteColor], NoshiFontSemibold(14), NoshiTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshMenu];
    [self load];
    [self loadTopic];
    [self loadStories];
}

/* a topic of a forum: its dialog has the forum flag cleared and a topic id, and the comments of a post carry the discussion flag on top of that */
- (BOOL)isTopic {
    return _dialog.topicId > 0 && !_dialog.discussion && !_dialog.saved;
}

- (void)loadTopic {
    if (![self isTopic]) return;
    NoshiWeakReference *me = _weak;
    if (_dialog.topicIconEmoji) {
        [NoshiCustomEmojiLoader loadDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:_dialog.topicIconEmoji]] session:self.session media:self.media
                                      documents:nil picture:^{
            NoshiChannelProfileController *profile = me.target;
            if (profile && profile->_topicIcon) profile->_topicIcon.image = NoshiTopicIconImage(profile->_dialog);
        }];
    }
    [self.session loadMessageCountOfDialog:_dialog completion:^(NSInteger count, NSString *errorName) {
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        if (errorName) {
            NSLog(@"noshigram: the messages of topic %d were not counted: %@", (int)profile->_dialog.topicId, errorName);
            return;
        }
        profile->_topicMessages = count;
        profile->_topicMessagesKnown = YES;
        profile->_status.text = [profile kindText];
    }];
}

- (NSString *)kindText {
    if ([self isTopic]) {
        if (!_topicMessagesKnown) return @"";
        return [NSString stringWithFormat:NSLocalizedString([@"topic.messages." stringByAppendingString:NoshiPluralForm(_topicMessages)], nil), (long)_topicMessages];
    }
    BOOL group = _full.megagroup || _dialog.kind == NOSHI_DIALOG_GROUP;
    /* the count of members under the name, as telegram for ios 4 had it, once it is known */
    if (_full.participants > 0) {
        NSString *key = [(group ? @"chat.members." : @"chat.subscribers.") stringByAppendingString:NoshiPluralForm(_full.participants)];
        return [NSString stringWithFormat:NSLocalizedString(key, nil), (long)_full.participants];
    }
    if (group) return NSLocalizedString(@"channel.kind.group", nil);
    return NSLocalizedString(_full.username.length ? @"channel.kind.public" : @"channel.kind.private", nil);
}

#define FULL_ATTEMPTS 4
#define FULL_RETRY_DELAY 2.0

- (void)load {
    [self loadFull];
    NoshiWeakReference *me = _weak;
    [_feed reload:^{ [(NoshiChannelProfileController *)me.target feedChanged]; }];
}

- (void)loadFull {
    NoshiWeakReference *me = _weak;
    [self retain];
    ++_fullAttempts;
    [self.session loadFullChannelOfDialog:_dialog completion:^(NoshiFullChannel *channel, NSString *errorName) {
        [self autorelease];
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        if (!channel) {
            NSLog(@"noshigram: the profile of channel %lld (topic %d) did not load, attempt %d: %@", profile->_dialog.peerId, (int)profile->_dialog.topicId,
                  (int)profile->_fullAttempts, errorName);
            if (profile->_fullAttempts < FULL_ATTEMPTS) [profile performSelector:@selector(loadFull) withObject:nil afterDelay:FULL_RETRY_DELAY];
            else [profile toast:NSLocalizedString(@"error.internal", nil)];
            return;
        }
        [profile->_full release];
        profile->_full = [channel retain];
        [profile showFull];
    }];
}

#pragma mark content

/* who is in the channel gets sound and, in a group, the chat; mute needs a member, so it waits for the full
   channel instead of showing a button that would fail */
- (BOOL)isMember {
    return _full != nil && (_joined || !(_full.membershipKnown ? _full.dialog.left : _dialog.left));
}

- (void)refreshActions {
    /* a supergroup is a channel to the list, and only the full channel tells it apart */
    _joinRow.title = NSLocalizedString(_full.megagroup || _dialog.kind == NOSHI_DIALOG_GROUP ? @"group.row.join" : @"channel.row.join", nil);
    BOOL muted = _full.muted;
    _soundRow.value = NSLocalizedString(muted ? @"profile.row.notifications.off" : @"profile.row.notifications.on", nil);
}

- (void)showFull {
    NoshiFullChannel *full = _full;
    _status.text = [self kindText];
    [self refreshActions];
    NSMutableArray *rows = [NSMutableArray array];
    if (full.about.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"channel.description", nil), full.about, nil]];
    if (full.shownLink.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"channel.link", nil), full.shownLink, nil]];
    [rows addObjectsFromArray:NoshiIdentityRows(_dialog.peerId, _dialog.photo)];
    [_info setRows:rows];
    /* the dialog of the list carries the community when the channel is in one; the full channel's own dialog is the fallback */
    [_community release];
    _community = [(_dialog.linkedCommunity ? _dialog.linkedCommunity : full.dialog.linkedCommunity) retain];
    _communityCard.hidden = _community == nil;
    if (_community) [_communityCard configureWithDialog:_community avatars:self.avatars];
    [self fillCounts];
    if ((full.megagroup || _dialog.kind == NOSHI_DIALOG_CHANNEL) && !_groupTabs) {
        /* the members of a broadcast channel are told to its administrators only, so the tab is not offered to anybody else */
        BOOL members = full.megagroup || full.creator || full.adminRights != 0;
        _groupTabs = [[NoshiGroupTabsView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media forUser:NO hidesMembers:!members];
        _groupTabs.delegate = self;
        [_head addSubview:_groupTabs];
    }
    [self refreshMenu];
    [self.view setNeedsLayout];
}

- (void)fillCounts {
    NoshiFullChannel *full = _full;
    _membersRow.title = NSLocalizedString(full.megagroup ? @"channel.members" : @"channel.subscribers", nil);
    _membersRow.value = [NSString stringWithFormat:@"%ld", (long)full.participants];
    _adminsRow.value = [NSString stringWithFormat:@"%ld", (long)full.admins];
    _bannedRow.value = [NSString stringWithFormat:@"%ld", (long)full.banned];
}

- (void)feedChanged {
    [_grid setTiles:_feed.tiles];
    BOOL any = _feed.items.count > 0;
    _giftsTitle.hidden = !any;
    NSString *text = @"";
    if (_feed.loaded && !any && _full.giftsAvailable) text = NSLocalizedString(@"gifts.empty", nil);
    if (![_empty.text isEqualToString:text]) _empty.text = text;
    [self.view setNeedsLayout];
}

- (void)giftGridReachedEnd:(NoshiGiftGridView *)grid {
    (void)grid;
    NoshiWeakReference *me = _weak;
    [_feed loadMore:^{ [(NoshiChannelProfileController *)me.target feedChanged]; }];
}

- (void)giftGrid:(NoshiGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _feed.items.count) return;
    NoshiGiftDetailController *detail = [[[NoshiGiftDetailController alloc] initWithSession:self.session gift:[_feed.items objectAtIndex:index] mine:NO
                                                                                        avatars:self.avatars media:self.media] autorelease];
    detail.ownerName = _dialog.title;
    detail.stickers = _stickers;
    [detail showInViewController:self];
}

#pragma mark layout

/* a pull of the list down past its top takes the wide photo away */
- (void)giftGrid:(NoshiGiftGridView *)grid didScrollToOffset:(CGFloat)offset {
    (void)grid;
    [_groupTabs hostDidScroll];
    [self heroFollowsPull:-(offset + _grid.topInset)];
}

- (void)layoutHead {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;
    CGFloat contentWidth = MIN(width - 32, 460);
    CGFloat x = (width - contentWidth) / 2;
    CGFloat wideHeight = _heroOpen ? _heroHeight : 0;
    /* the photo reaches up under the bar and the status bar: its frame begins above the head by the inset of the list */
    if (_hero) _hero.frame = _heroOpen ? CGRectMake(0, -_grid.topInset, width, _grid.topInset + wideHeight) : _heroCircle;
    _avatar.frame = CGRectMake(15, 16, AVATAR, AVATAR);
    _topicIcon.frame = _avatar.frame;
    _storyRing.frame = CGRectInset(_avatar.frame, -[NoshiStoryRing outset], -[NoshiStoryRing outset]);
    /* the name and the status stand beside the photo, as a block in the middle of the head */
    CGFloat textWidth = width - NAME_X - 14;
    _name.font = NoshiFontMedium(20);
    CGFloat nameHeight = MAX(24, ceil([_name sizeThatFits:CGSizeMake(textWidth, 200)].height));
    CGFloat block = nameHeight + 4 + 20;
    CGFloat headHeight = MAX(HEAD_HEIGHT, block + 32);
    CGFloat nameY = floor((headHeight - block) / 2);
    _name.frame = CGRectMake(NAME_X, nameY, textWidth, nameHeight);
    _status.frame = CGRectMake(NAME_X, nameY + nameHeight + 4, textWidth, 20);
    _headPanel.frame = CGRectMake(0, 0, width, headHeight);
    NoshiFitInfoGroupLines(_headPanel, NO);
    CGFloat y = (_heroOpen ? MAX(wideHeight, headHeight) : headHeight) + GAP;
    CGFloat height = [_info heightForWidth:width];
    _info.hidden = height <= 0;
    if (!_info.hidden) {
        _info.frame = CGRectMake(0, y, width, height);
        y += height + GAP;
    }
    /* join while outside; inside, the chat of a group, inviting to a supergroup, and the link of a public one */
    BOOL member = [self isMember];
    BOOL group = _full.megagroup || _dialog.kind == NOSHI_DIALOG_GROUP;
    NSMutableArray *actions = [NSMutableArray array];
    if (_full && !member) [actions addObject:_joinRow];
    if (member && group) [actions addObject:_messageRow];
    if (member && _full.megagroup) [actions addObject:_addRow];
    if (_full.webLink.length) [actions addObject:_linkRow];
    CGFloat actionsHeight = NoshiLayoutInfoGroup(_actionsGroup, actions, y, width);
    if (actionsHeight > 0) y += actionsHeight + GAP;
    CGFloat soundHeight = NoshiLayoutInfoGroup(_soundGroup, member ? [NSArray arrayWithObject:_soundRow] : [NSArray array], y, width);
    if (soundHeight > 0) y += soundHeight + GAP;
    if (!_communityCard.hidden) {
        _communityCard.frame = CGRectMake(0, y, width, LINKED_HEIGHT);
        _communityLine.frame = CGRectMake(0, LINKED_HEIGHT - 1.0f / NoshiScreenScale(), width, 1.0f / NoshiScreenScale());
        y += LINKED_HEIGHT + GAP;
    }
    NSMutableArray *counts = [NSMutableArray array];
    if (_full.participants > 0) [counts addObject:_membersRow];
    if (_full.admins > 0) [counts addObject:_adminsRow];
    if (_full.banned > 0) [counts addObject:_bannedRow];
    CGFloat countsHeight = NoshiLayoutInfoGroup(_countsGroup, counts, y, width);
    if (countsHeight > 0) y += countsHeight + GAP;
    if (_groupTabs) {
        CGFloat tabsHeight = [_groupTabs heightForWidth:width];
        _groupTabs.frame = CGRectMake(0, y, width, tabsHeight);
        y += tabsHeight + GAP;
    }
    if (!_giftsTitle.hidden) {
        _giftsTitle.frame = CGRectMake(15, y, width - 30, 20);
        y += 28;
    }
    CGSize empty = _empty.text.length ? [_empty sizeThatFits:CGSizeMake(contentWidth - 16, 200)] : CGSizeZero;
    _empty.frame = CGRectMake(x + 8, y + 8, contentWidth - 16, empty.height);
    y += empty.height ? empty.height + 24 : 0;
    if (fabs(y - _headHeight) > 0.5 || fabs(width - _headWidth) > 0.5) {
        _headHeight = y;
        _headWidth = width;
        _head.frame = CGRectMake(0, 0, width, y);
        if (_heroMoving) [_grid setHeaderViewAnimated:_head];
        else _grid.headerView = _head;
    }
}

- (void)layoutBody:(CGRect)body {
    [_grid setFrame:_heroUnderBar ? CGRectMake(body.origin.x, 0, body.size.width, CGRectGetMaxY(body)) : body topInset:_heroUnderBar ? body.origin.y : 0];
    _toast.frame = CGRectMake(CGRectGetMidX(body) - 80, body.origin.y + 12, 160, 28);
    [self layoutHead];
}

#pragma mark group tabs

/* a person is picked from the contacts and added at once; the member list under the tabs is read again when the server took them */
- (void)addMembers {
    NoshiContactPickerController *picker = [[[NoshiContactPickerController alloc] initWithSession:self.session avatars:self.avatars media:self.media] autorelease];
    NoshiWeakReference *me = _weak;
    picker.pickHandler = ^(NoshiDialog *user) {
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        [profile.navigationController popViewControllerAnimated:YES];
        [profile invite:user];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)invite:(NoshiDialog *)user {
    NoshiWeakReference *me = _weak;
    [self retain];
    [self.session inviteUserDialog:user toDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        if (errorName) {
            NSLog(@"noshigram: inviting %lld to channel %lld failed: %@", user.peerId, profile->_dialog.peerId, errorName);
            NoshiGiftAlert(nil, NoshiChannelErrorText(errorName));
            return;
        }
        [profile toast:NSLocalizedString(@"group.action.added", nil)];
        [profile load];
        [profile reloadGroupTabs];
    }];
}

- (void)reloadGroupTabs {
    [_groupTabs reloadMembers];
}

- (void)groupTabsDidResize:(NoshiGroupTabsView *)tabs {
    (void)tabs;
    [self.view setNeedsLayout];
}

- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenPerson:(NoshiPerson *)person {
    (void)tabs;
    if (!person) return;
    NoshiUserProfileController *profile = [[[NoshiUserProfileController alloc] initWithSession:self.session dialog:[NoshiDialog dialogWithPerson:person]
                                                                                           avatars:self.avatars media:self.media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}

- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMessage:(NoshiMessage *)message {
    (void)tabs;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    chat.startMessageId = message.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}

/* a picture or video of the media tab opens in the viewer, as in the chat itself, and not the chat at the place where it was sent */
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMedia:(NoshiMessage *)message among:(NSArray *)messages {
    (void)tabs;
    NoshiMediaViewer *viewer = [[[NoshiMediaViewer alloc] initWithMessages:messages selected:message media:self.media senderNames:nil
                                                                     chatTitle:_dialog.title] autorelease];
    NoshiWeakReference *weakScreen = [NoshiWeakReference referenceTo:self];
    viewer.showInChatHandler = ^(NoshiMessage *shown) {
        id me = weakScreen.target;
        if (me) [me groupTabs:nil didOpenMessage:shown];
    };
    [self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark actions

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

- (void)toggleMute {
    if (!_full || _muteBusy) return;
    _muteBusy = YES;
    BOOL mute = !_full.muted;
    NoshiWeakReference *me = _weak;
    [self retain];
    [self.session performAction:mute ? NoshiChatCommandMute : NoshiChatCommandUnmute onDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        profile->_muteBusy = NO;
        if (errorName) {
            [profile toast:NoshiGiftErrorText(errorName)];
            return;
        }
        /* the answer carries no new state, so the screen asks the server again for the full channel */
        [profile load];
    }];
}

- (void)join {
    if (!_full || _joinBusy) return;
    _joinBusy = YES;
    _joinRow.enabled = NO;
    NoshiWeakReference *me = _weak;
    [self retain];
    [self.session joinChannelOfDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        profile->_joinBusy = NO;
        profile->_joinRow.enabled = YES;
        if (errorName) {
            NSLog(@"noshigram: joining channel %lld failed: %@", profile->_dialog.peerId, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
        profile->_joined = YES;
        /* the answer carries no new state, so the screen asks the server again for the full channel */
        [profile load];
    }];
}

- (void)report {
    [NoshiReportFlow startForDialog:_dialog session:self.session host:self done:nil];
}

/* a group has its chat to go to: the one this profile came from when that is right below, a new one otherwise */
- (void)openMessages {
    NoshiProfileShowChat(self, self.session, _dialog, self.avatars, self.media, _stickers);
}

- (void)openDiscussion {
    NoshiDialog *linked = _full.linked;
    if (!linked) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:linked avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)openCommunity {
    if (!_community) return;
    [self.navigationController pushViewController:NoshiCommunityScreen(self.session, _community, nil, self.avatars, self.media, _stickers, nil) animated:YES];
}

- (void)openQr {
    if (!_full.webLink.length) return;
    [self.navigationController pushViewController:[[[NoshiProfileQrController alloc] initWithSession:self.session channel:_full avatars:self.avatars
                                                                                                  media:self.media] autorelease] animated:YES];
}

- (void)openManage {
    if (!_full.isAdmin) return;
    NoshiChannelManageController *manage = [[[NoshiChannelManageController alloc] initWithSession:self.session channel:_full avatars:self.avatars
                                                                                                media:self.media] autorelease];
    NoshiWeakReference *me = _weak;
    manage.changedHandler = ^(NoshiFullChannel *channel) {
        NoshiChannelProfileController *profile = me.target;
        if (!profile) return;
        [profile->_full release];
        profile->_full = [channel retain];
        [profile showFull];
    };
    [self.navigationController pushViewController:manage animated:YES];
}

#pragma mark menu

typedef enum { NoshiChannelMenuCopyLink, NoshiChannelMenuManage, NoshiChannelMenuDiscussion, NoshiChannelMenuNotifications, NoshiChannelMenuReport } NoshiChannelMenuEntry;

- (void)refreshMenu {
    if (!_full) {
        [self setActionSymbol:NoshiSymbolEllipsis label:nil handler:nil];
        return;
    }
    NoshiWeakReference *me = _weak;
    [self setActionSymbol:NoshiSymbolEllipsis label:NSLocalizedString(@"profile.more", nil)
                  handler:^{ [(NoshiChannelProfileController *)me.target showMenu]; }];
}

- (void)showMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *entries = [NSMutableArray array];
    NoshiSymbol symbols[5];
    if (_full.webLink.length) {
        symbols[titles.count] = NoshiSymbolLink;
        [titles addObject:NSLocalizedString(@"profile.qr.copy", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiChannelMenuCopyLink]];
    }
    if ([self isMember] && _full.isAdmin) {
        symbols[titles.count] = NoshiSymbolGear;
        [titles addObject:NSLocalizedString(@"channel.action.manage", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiChannelMenuManage]];
    }
    if (_full.linked) {
        symbols[titles.count] = NoshiSymbolChats;
        [titles addObject:NSLocalizedString(@"channel.menu.discussion", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiChannelMenuDiscussion]];
    }
    symbols[titles.count] = NoshiSymbolBell;
    [titles addObject:NSLocalizedString(@"notif.chat.header", nil)];
    [entries addObject:[NSNumber numberWithInt:NoshiChannelMenuNotifications]];
    symbols[titles.count] = NoshiSymbolReport;
    [titles addObject:NSLocalizedString(@"report.title", nil)];
    [entries addObject:[NSNumber numberWithInt:NoshiChannelMenuReport]];
    NoshiWeakReference *me = _weak;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        NoshiChannelProfileController *profile = me.target;
        if (!profile || index >= entries.count) return;
        switch ([[entries objectAtIndex:index] intValue]) {
        case NoshiChannelMenuCopyLink: [profile copyLink]; break;
        case NoshiChannelMenuManage: [profile openManage]; break;
        case NoshiChannelMenuDiscussion: [profile openDiscussion]; break;
        case NoshiChannelMenuNotifications:
            [profile.navigationController pushViewController:[[[NoshiNotificationsChatController alloc] initWithSession:profile.session media:profile.media peerKind:profile->_dialog.peerKind
                                                                                                                  peerId:profile->_dialog.peerId peerHash:profile->_dialog.peerHash
                                                                                                                 channel:profile->_dialog.kind == NOSHI_DIALOG_CHANNEL topic:0
                                                                                                                   title:profile->_dialog.title] autorelease] animated:YES];
            break;
        case NoshiChannelMenuReport: [profile report]; break;
        }
    }] autorelease];
    [menu showInView:self.view anchor:[self actionSymbolAnchor]];
}

- (void)copyLink {
    if (!_full.webLink.length) return;
    [UIPasteboard generalPasteboard].string = _full.webLink;
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

@end
