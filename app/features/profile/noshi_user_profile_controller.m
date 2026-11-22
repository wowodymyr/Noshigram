#import "noshi_user_profile_controller.h"
#import "noshi_media_viewer.h"
#import "noshi_notifications_chat_controller.h"
#import "noshi_group_tabs_view.h"
#import "noshi_chat_settings.h"
#import "noshi_contact_edit_controller.h"
#import "noshi_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_avatar_viewer.h"
#import "noshi_channel_card.h"
#import "noshi_name_badge.h"
#import "noshi_chat_controller.h"
#import "noshi_emoji_label.h"
#import "noshi_gift_catalog_controller.h"
#import "noshi_gift_detail_controller.h"
#import "noshi_gift_grid_view.h"
#import "noshi_info_card_view.h"
#import "noshi_info_rows.h"
#import "noshi_music_list_controller.h"
#import "noshi_music_pill.h"
#import "noshi_profile_gifts_view.h"
#import "noshi_popup_menu.h"
#import "noshi_profile_action.h"
#import "noshi_profile_backdrop_view.h"
#import "noshi_profile_colors.h"
#import "noshi_custom_emoji.h"
#import "noshi_profile_chat.h"
#import "noshi_profile_qr_controller.h"
#import "noshi_alert.h"
#import "noshi_gift_folder_bar.h"
#import "noshi_image_decoder.h"
#import "noshi_lite_mode.h"
#import "noshi_lottie_view.h"
#import "noshi_platform.h"
#import "noshi_session_bots.h"
#import "noshi_profile_feed.h"
#import "noshi_report_flow.h"
#import "noshi_session_channels.h"
#import "noshi_session_profile.h"
#import "noshi_session_actions.h"
#import "noshi_avatar_viewer.h"
#import "noshi_profile_hero_view.h"
#import "noshi_star_gift.h"
#import "noshi_status_label.h"
#import "noshi_rating_view.h"
#import "noshi_typing_board.h"
#import "noshi_story.h"
#import "noshi_story_ring.h"
#import "noshi_story_viewer_controller.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_weak_reference.h"

/* the user info of telegram for ios 4: a white head of 97 points with the photo of 66 at the left, the name and the status beside it and the round key of a call at the
   right, then white groups of rows with 24 points of the grey ground between them */
#define AVATAR 66.0
#define HEAD_HEIGHT 97.0
#define NAME_X 92.0
#define SECTION_GAP NOSHI_INFO_SECTION_GAP
#define GAP 14.0

/* how far the list is pulled down past its top before the wide photo goes back to the circle, in points */
/* the pull of the list down past its top, in points: the first opens the round photo wide, the second goes on to the photos on the whole screen; the
   scroll of the head up by the third takes the wide photo back to the circle */
#define HERO_OPEN_PULL 60.0
#define HERO_VIEW_PULL 130.0
#define HERO_FOLD_SCROLL 90.0
#define BAR_SHADE_AFTER 24.0

@interface NoshiUserProfileController () <NoshiGiftGridDelegate, NoshiGroupTabsDelegate, NoshiGiftFolderBarDelegate, UIGestureRecognizerDelegate> {
    NoshiGiftFolderBar *_folderBar;
    NoshiDialog *_dialog;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;
    NoshiGiftGridView *_grid;
    UIView *_head;
    NoshiAvatarView *_avatar;
    NoshiProfileHeroView *_hero;
    /* the photo opened wide in the head: the frame it was a circle in, the height it grows to, and whether it is open */
    CGRect _heroCircle;
    CGFloat _heroHeight;
    BOOL _heroOpen;
    /* the list runs under the bar while the wide photo is open, so the photo can reach the top of the screen */
    BOOL _heroUnderBar;
    /* the ink the cards wear on the colored ground of a collectible profile, to put back when the wide photo closes */
    UIColor *_cardInk;
    BOOL _heroMoving;
    BOOL _viewerWanted;
    NoshiStoryRing *_storyRing;
    BOOL _storiesShown;
    NoshiEmojiLabel *_name;
    /* the colored ground behind the head when the person wears a collectible color or status */
    NoshiProfileBackdropView *_backdrop;
    CGFloat _backdropBottom;
    /* the name of the collectible the person wears and the emoji status it belongs to: a tap on the emoji says the name */
    NSString *_backdropTitle;
    long long _backdropStatusDocument;
    /* the emoji status of the user when it moves: drawn over the still picture the name already holds, at the place the name leaves for it */
    NoshiLottieView *_statusAnimation;
    long long _statusAnimationDocument;
    NSUInteger _statusAnimationToken;
    NoshiStatusLabel *_status;
    NoshiRatingBadge *_ratingBadge;
    NoshiUserAction *_messageAction;
    NoshiUserAction *_soundAction;
    NoshiUserAction *_callAction;
    NoshiUserAction *_videoAction;
    NoshiUserAction *_storiesAction;
    /* the white ground of the head, the round key of a call in it, and the groups of rows under the information */
    UIView *_headPanel;
    UIButton *_callButton;
    UIView *_actionsGroup;
    NoshiInfoRow *_messageRow;
    NoshiInfoRow *_videoRow;
    NoshiInfoRow *_storiesRow;
    UIView *_soundGroup;
    NoshiInfoRow *_soundRow;
    UIView *_musicGroup;
    NoshiMusicPill *_music;
    NoshiProfileGiftsView *_pinnedGifts;
    NoshiChannelCard *_channelCard;
    NoshiInfoCardView *_info;
    /* gifts, Media, Files and Links of the chat with this person */
    NoshiGroupTabsView *_tabs;
    UILabel *_empty;
    UILabel *_toast;
    NoshiProfileFeed *_feed;
    NoshiFullUser *_fullUser;
    NoshiStoryPeer *_storyPeer;
    NSUInteger _fullUserGeneration;
    NSUInteger _storiesGeneration;
    BOOL _muted;
    BOOL _muteBusy;
    CGFloat _headHeight;
    CGFloat _headWidth;
}
@end

@implementation NoshiUserProfileController

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _stickers = [stickers retain];
    _muted = dialog.muted;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _feed = [[NoshiProfileFeed alloc] initWithSession:session kind:NoshiFeedGifts owner:dialog];
    /* the bar says Info, as it did in telegram for ios 4; the name is in the head under it */
    self.screenTitle = NSLocalizedString(@"profile.row.info", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_dialog release];
    [_stickers release];
    [_grid release];
    [_head release];
    [_hero release];
    [_cardInk release];
    [_avatar release];
    [_storyRing release];
    [_name release];
    [_statusAnimation release];
    [_backdrop release];
    [_backdropTitle release];
    [_status release];
    [_ratingBadge release];
    [_messageAction release];
    [_soundAction release];
    [_callAction release];
    [_videoAction release];
    [_storiesAction release];
    [_headPanel release];
    [_callButton release];
    [_actionsGroup release];
    [_messageRow release];
    [_videoRow release];
    [_storiesRow release];
    [_soundGroup release];
    [_soundRow release];
    [_musicGroup release];
    [_music release];
    [_pinnedGifts release];
    [_channelCard release];
    [_info release];
    _tabs.delegate = nil;
    _folderBar.delegate = nil;
    [_folderBar release];
    [_tabs release];
    [_empty release];
    [_toast release];
    [_feed release];
    [_fullUser release];
    [_storyPeer release];
    [super dealloc];
}

static UILabel *NoshiUserLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

/* the full profiles seen in this run of the app, by session and person, so opening one again shows it whole at once */
static NSMutableDictionary *NoshiUserProfileMemory(void) {
    static NSMutableDictionary *memory = nil;
    if (!memory) memory = [[NSMutableDictionary alloc] init];
    return memory;
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
    _avatar.deleted = _dialog.deleted;
    [_avatar setPhoto:_dialog.photo cache:self.avatars];
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)] autorelease]];
    _pinnedGifts = [[NoshiProfileGiftsView alloc] initWithMedia:self.media];
    [_head addSubview:_pinnedGifts];
    [_head addSubview:_avatar];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.textColor = NoshiColorTitle();
    _name.textAlignment = NoshiTextAlignmentLeft;
    _name.dropsUndrawable = YES;
    /* a long name goes on a second line instead of ending in dots */
    _name.numberOfLines = 2;
    [self showName:_dialog.title emojiStatus:_dialog.emojiStatus premium:_dialog.premium];
    [_head addSubview:_name];
    /* the name draws no touches itself, so the tap on the hammer is taken by the header and placed by where the name ends */
    UITapGestureRecognizer *hammerTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headTapped:)] autorelease];
    hammerTap.delegate = self;
    [_head addGestureRecognizer:hammerTap];
    _status = [[NoshiStatusLabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.font = [UIFont systemFontOfSize:15];
    _status.textAlignment = NoshiTextAlignmentLeft;
    [self refreshStatus];
    [_head addSubview:_status];
    _ratingBadge = [[NoshiRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    [_ratingBadge addTarget:self action:@selector(openRating) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_ratingBadge];

    _messageAction = [[NoshiUserAction alloc] initWithSymbol:NoshiSymbolProfileMessage title:NSLocalizedString(@"profile.action.chat", nil)];
    [_messageAction addTarget:self action:@selector(openMessages) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_messageAction];
    _soundAction = [[NoshiUserAction alloc] initWithSymbol:NoshiSymbolProfileMute title:NSLocalizedString(@"profile.action.sound", nil)];
    [_soundAction addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_soundAction];
    [self refreshSound];
    /* a call goes to a person: not to a bot or to the saved messages */
    _callAction = [[NoshiUserAction alloc] initWithSymbol:NoshiSymbolPhone title:NSLocalizedString(@"profile.action.call", nil)];
    _callAction.hidden = ![self canCallPerson];
    [_callAction addTarget:self action:@selector(startCall) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_callAction];
    _videoAction = [[NoshiUserAction alloc] initWithSymbol:NoshiSymbolVideoCamera title:NSLocalizedString(@"profile.action.video", nil)];
    _videoAction.hidden = ![self canCallPerson];
    [_videoAction addTarget:self action:@selector(startVideoCall) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_videoAction];
    _storiesAction = [[NoshiUserAction alloc] initWithSymbol:NoshiSymbolPlay title:NSLocalizedString(@"profile.tab.stories", nil)];
    _storiesAction.hidden = YES;
    [_storiesAction addTarget:self action:@selector(openStories) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_storiesAction];
    /* the cards of the modern head stay made for the code that dresses them, and are never shown: their actions are the key and the rows of telegram for ios 4 */
    for (NoshiUserAction *card in [NSArray arrayWithObjects:_messageAction, _soundAction, _callAction, _videoAction, _storiesAction, nil]) card.hidden = YES;
    _callButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_callButton setImage:NoshiSymbolImage(NoshiSymbolPhone, 26, NoshiColorAccent()) forState:UIControlStateNormal];
    _callButton.accessibilityLabel = NSLocalizedString(@"profile.action.call", nil);
    _callButton.hidden = ![self canCallPerson];
    [_callButton addTarget:self action:@selector(startCall) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_callButton];
    _actionsGroup = NoshiNewInfoGroup();
    _messageRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.message", nil) accent:YES chevron:NO target:self action:@selector(openMessages)];
    _videoRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.video", nil) accent:YES chevron:NO target:self action:@selector(startVideoCall)];
    _storiesRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.tab.stories", nil) accent:YES chevron:NO target:self action:@selector(openStories)];
    for (NoshiInfoRow *row in [NSArray arrayWithObjects:_messageRow, _videoRow, _storiesRow, nil]) [_actionsGroup addSubview:row];
    [_head addSubview:_actionsGroup];
    _soundGroup = NoshiNewInfoGroup();
    _soundRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.notifications", nil) accent:NO chevron:NO target:self action:@selector(toggleMute)];
    [_soundGroup addSubview:_soundRow];
    [_head addSubview:_soundGroup];
    [self refreshSound];
    _musicGroup = NoshiNewInfoGroup();
    [_head addSubview:_musicGroup];

    _music = [[NoshiMusicPill alloc] init];
    _music.media = self.media;
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    NoshiWeakReference *musicMe = _weak;
    _music.contentHandler = ^{ [(NoshiUserProfileController *)musicMe.target musicContentChanged]; };
    [_musicGroup addSubview:_music];

    _channelCard = [[NoshiChannelCard alloc] init];
    _channelCard.hidden = YES;
    [_channelCard addTarget:self action:@selector(openChannel) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_channelCard];
    _info = [[NoshiInfoCardView alloc] init];
    NoshiWeakReference *me = _weak;
    _info.codeCaption = NSLocalizedString(@"profile.username", nil);
    _info.codeHandler = ^{ [(NoshiUserProfileController *)me.target openCode]; };
    _info.copyHandler = ^{ [(NoshiUserProfileController *)me.target toast:NSLocalizedString(@"profile.copied", nil)]; };
    [_head addSubview:_info];
    _tabs = [[NoshiGroupTabsView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media forUser:YES];
    _tabs.delegate = self;
    [_head addSubview:_tabs];
    /* the folders of the gifts of this person, shown over the gifts while that tab is chosen */
    _folderBar = [[NoshiGiftFolderBar alloc] initWithSession:self.session dialog:_dialog mine:NO];
    _folderBar.delegate = self;
    [_head addSubview:_folderBar];
    _empty = NoshiUserLabel(NoshiColorSecondary(), NoshiFontRegular(15), NoshiTextAlignmentCenter);
    _empty.numberOfLines = 0;
    [_head addSubview:_empty];
    _grid.headerView = _head;

    _toast = NoshiUserLabel([UIColor whiteColor], NoshiFontSemibold(14), NoshiTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
}

/* the line under the name: what the person is doing now, or on line in the accent color, or when they were last seen */
- (void)typingChanged:(NSNotification *)note {
    if (NoshiTypingChangeConcerns(note, _dialog)) [self refreshStatus];
}

- (void)refreshStatus {
    if (self.isViewLoaded) [self.view setNeedsLayout];
    if (_dialog.kind == NOSHI_DIALOG_BOT) {
        [_status setStatus:NSLocalizedString(@"profile.bot", nil) kind:NoshiStatusPlain];
        return;
    }
    NoshiTypingBoard *board = self.session.typing;
    NSString *typing = NoshiTypingStatusText([board actionInDialog:_dialog], [board countInDialog:_dialog]);
    if (typing) {
        [_status setStatus:typing kind:NoshiStatusTyping];
        return;
    }
    BOOL service = _dialog.peerKind == 1 && _dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID;
    NSString *seen = service ? NSLocalizedString(@"chat.status.telegram", nil) : NoshiLastSeenText(_dialog.presence, _dialog.seen);
    /* a photo the person set for this contact is a thing only they see, so the line says it after the time of the visit */
    if (!service && _fullUser.hasPersonalPhoto) seen = [NSString stringWithFormat:@"%@ \u2022 %@", seen, NSLocalizedString(@"profile.status.photo.set", nil)];
    [_status setStatus:seen kind:!service && _dialog.presence == NOSHI_PRESENCE_ONLINE ? NoshiStatusOnline : NoshiStatusPlain];
}

- (void)viewDidLoad {
    NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
    [super viewDidLoad];
    NSLog(@"noshigram: the profile view loaded in %.0f ms", ([NSDate timeIntervalSinceReferenceDate] - began) * 1000);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typingChanged:) name:NoshiTypingDidChangeNotification object:self.session.typing];
    [self refreshMenu];
    [self load];
    NSLog(@"noshigram: the profile screen is set up");
}

/* the ring round the picture follows the stories of the person: coloured while one is unseen, grey once all were
   seen */
- (void)loadStories {
    NoshiWeakReference *me = _weak;
    NSUInteger generation = ++_storiesGeneration;
    [self retain];
    [self.session loadStoriesOfDialog:_dialog completion:^(NoshiStoryPeer *peer, NSArray *stories, NSString *errorName) {
        [self autorelease];
        NoshiUserProfileController *profile = me.target;
        if (!profile || generation != profile->_storiesGeneration || errorName) return;
        [profile->_storyPeer release];
        profile->_storyPeer = stories.count ? [peer retain] : nil;
        profile->_storyRing.hidden = !profile->_storyPeer;
        if (profile->_storyPeer) [profile->_storyRing setPeer:profile->_storyPeer];
        [profile.view setNeedsLayout];
    }];
}

- (void)avatarTapped {
    if (_storyPeer) [self openStories];
    else [self openHero];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_storiesShown) [self loadStories];
    _storiesShown = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_statusAnimation setPlaying:!_hero];
    NSLog(@"noshigram: the profile screen is on screen");
}

/* the recognizer takes the touches over the name only: one that took every touch of the header cancelled the controls under it, the pill of the music among them */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return _backdropTitle.length && CGRectContainsPoint(CGRectInset(_name.frame, 0, -8), [touch locationInView:_head]);
}

- (void)headTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded) return;
    CGPoint point = [tap locationInView:_name];
    long long document = [_name customEmojiAtPoint:point];
    if (_backdropTitle.length && document && document == _backdropStatusDocument && point.y >= -8 && point.y <= _name.bounds.size.height + 8) {
        [self toast:_backdropTitle];
    }
}

- (NSString *)memoryKey {
    return [NSString stringWithFormat:@"%p:%lld", self.session, _dialog.peerId];
}

- (void)load {
    NoshiWeakReference *me = _weak;
    NSUInteger generation = ++_fullUserGeneration;
    /* the profile as it was last seen fills the page at once, so the song, the rows and the keys stand in place from the first frame and the answer only corrects them */
    NoshiFullUser *known = [NoshiUserProfileMemory() objectForKey:[self memoryKey]];
    if (known) {
        [_fullUser release];
        _fullUser = [known retain];
        _hero.publicPhoto = known.publicPhoto;
        [self showFull];
    }
    [self retain];
    [self.session loadFullUserOfDialog:_dialog completion:^(NoshiFullUser *user, NSString *errorName) {
        [self autorelease];
        NoshiUserProfileController *profile = me.target;
        if (!profile || generation != profile->_fullUserGeneration) return;
        if (!user) {
            NSLog(@"noshigram: the profile of %lld did not load: %@", profile->_dialog.peerId, errorName);
            return;
        }
        NSMutableDictionary *memory = NoshiUserProfileMemory();
        if (memory.count > 64) [memory removeAllObjects];
        [memory setObject:user forKey:[profile memoryKey]];
        BOOL first = profile->_fullUser == nil;
        [profile->_fullUser release];
        profile->_fullUser = [user retain];
        profile->_hero.publicPhoto = user.publicPhoto;
        /* a profile opened for the first time gets its song and rows while it is on screen: they fade in with the rows moving under them, not in one jump */
        if (first && profile.isViewLoaded && profile.view.window) {
            [UIView transitionWithView:profile.view duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:^{ [profile showFull]; [profile.view layoutIfNeeded]; } completion:nil];
        } else {
            [profile showFull];
        }
    }];
    [self loadStories];
    [_folderBar reload];
    [_feed reload:^{ [(NoshiUserProfileController *)me.target giftsChanged]; }];
}

#pragma mark folders

- (void)giftFolderBar:(NoshiGiftFolderBar *)bar didSelectFolder:(NoshiGiftFolder *)folder {
    (void)bar;
    [self reloadFeedOfFolder:folder.folderId];
}

- (void)giftFolderBarDidChange:(NoshiGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged {
    if (selectionChanged) [self reloadFeedOfFolder:bar.selectedFolder.folderId];
    [self.view setNeedsLayout];
}

- (void)reloadFeedOfFolder:(int32_t)folderId {
    NoshiWeakReference *me = _weak;
    _feed.folderId = folderId;
    [_feed reload:^{ [(NoshiUserProfileController *)me.target giftsChanged]; }];
}

#pragma mark content

/* the name with the custom emoji status of the user after it, or the Premium star; the picture is fetched once and the name is drawn
   again when it lands */
- (void)showName:(NSString *)name emojiStatus:(long long)emojiStatus premium:(BOOL)premium {
    NSArray *entities = nil;
    long long badge = _dialog.peerKind == 1 && _dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID ? NoshiDialogBadgeDocument(_dialog) : (_dialog.saved ? 0 : NoshiBadgeDocument(emojiStatus, premium));
    _name.text = NoshiNameWithBadge(name, badge, &entities);
    _name.entities = entities;
    /* only a status that is the badge drawn after the name has a place to move in */
    [self animateStatus:badge == emojiStatus ? emojiStatus : 0];
    if (!emojiStatus) return;
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:emojiStatus]], self.session, self.media, ^{
        NoshiUserProfileController *profile = weak.target;
        if (profile) [profile->_name setNeedsDisplay];
    });
}

- (void)dropStatusAnimation {
    ++_statusAnimationToken;
    _name.hiddenCustomEmoji = 0;
    _statusAnimationDocument = 0;
    [_statusAnimation removeFromSuperview];
    [_statusAnimation release];
    _statusAnimation = nil;
}

/* a status that is an animation (tgs, or a video sticker) is fetched once and plays in place of its still picture; a plain one stays as it is drawn. The same
   status again only puts the animation back at the place the name now leaves for it */
- (void)animateStatus:(long long)document {
    if (document && document == _statusAnimationDocument) {
        [self placeStatusAnimation];
        return;
    }
    [self dropStatusAnimation];
    if (!document || !NoshiLiteEnabled(NOSHI_LITE_EMOJI_CHAT)) return;
    _statusAnimationDocument = document;
    NSUInteger token = ++_statusAnimationToken;
    NoshiWeakReference *weak = _weak;
    [self.session loadCustomEmojiDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] completion:^(NSArray *documents, NSString *errorName) {
        NoshiUserProfileController *profile = weak.target;
        if (!profile || token != profile->_statusAnimationToken) return;
        NoshiCustomEmojiDocument *found = documents.count ? [documents objectAtIndex:0] : nil;
        if (!found) {
            if (errorName) NSLog(@"noshigram: the status emoji %lld was not looked up: %@", document, errorName);
            return;
        }
        if (!found.file || (found.format != NOSHI_STICKER_ANIMATED && found.format != NOSHI_STICKER_VIDEO)) return;
        NSString *key = found.file.key;
        [profile.media loadDataForFile:found.file completion:^(NSData *data) {
            NoshiUserProfileController *again = weak.target;
            if (!again || token != again->_statusAnimationToken) return;
            NoshiFileFormat format = data ? NoshiFileFormatOfData(data) : NoshiFileFormatUnknown;
            if (format != NoshiFileFormatGzip && format != NoshiFileFormatMatroska) {
                NSLog(@"noshigram: the status emoji %@ did not load as tgs or webm", key);
                return;
            }
            [again showStatusAnimation:data key:key];
        }];
    }];
}

- (void)showStatusAnimation:(NSData *)data key:(NSString *)key {
    NoshiLottieView *view = [[[NoshiLottieView alloc] initWithPackedData:data key:key] autorelease];
    view.userInteractionEnabled = NO;
    view.backgroundColor = [UIColor clearColor];
    /* a status that lands while the photo is wide stays hidden with the name */
    view.alpha = _hero ? 0 : 1;
    [_statusAnimation removeFromSuperview];
    [_statusAnimation release];
    _statusAnimation = [view retain];
    NoshiWeakReference *weak = _weak;
    NSUInteger token = _statusAnimationToken;
    view.firstFrameHandler = ^{
        NoshiUserProfileController *profile = weak.target;
        if (profile && token == profile->_statusAnimationToken)
            profile->_name.hiddenCustomEmoji = profile->_statusAnimationDocument;
    };
    [_head addSubview:view];
    [self placeStatusAnimation];
    [view setPlaying:self.isViewLoaded && self.view.window != nil && !_hero];
}

/* the name keeps the still picture until the animation has its first frame */
- (void)placeStatusAnimation {
    if (!_statusAnimation) return;
    CGRect box = [_name customEmojiRect:_statusAnimationDocument];
    if (CGRectIsNull(box)) {
        _statusAnimation.hidden = YES;
        return;
    }
    CGFloat side = box.size.width;
    _statusAnimation.frame = [_head convertRect:CGRectMake(box.origin.x, CGRectGetMidY(box) - side / 2, side, side) fromView:_name];
    _statusAnimation.hidden = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_statusAnimation setPlaying:NO];
}

/* the head takes the colors of the person: a collectible's own, or those of the color they picked from the server's list, which are asked for once */
- (void)applyBackdropOfPerson:(NoshiPerson *)person {
    if (person.hasBackdrop) {
        [_backdropTitle release];
        _backdropTitle = [person.backdropTitle copy];
        _backdropStatusDocument = person.emojiStatus;
        [self showBackdropCenter:person.backdropCenter edge:person.backdropEdge pattern:person.backdropPattern text:person.backdropText document:person.backdropPatternDocument];
        return;
    }
    if (!person.hasProfileColor) return;
    NoshiWeakReference *weak = _weak;
    int32_t colorId = (int32_t)person.profileColorId;
    long long emoji = person.profileColorEmoji;
    [NoshiProfileColors loadWithSession:self.session completion:^{
        NoshiUserProfileController *profile = weak.target;
        uint32_t center = 0, edge = 0;
        if (!profile || ![NoshiProfileColors blendForColorId:colorId dark:NoshiThemeIsDark() center:&center edge:&edge]) return;
        [profile showBackdropCenter:center edge:edge pattern:0xFFFFFF text:0xFFFFFF document:emoji];
    }];
}

/* the color the bar fills with once the content has scrolled under it: the edge of the ground, darker */
static UIColor *NoshiDarkenedBackdrop(uint32_t rgb) {
    const CGFloat keep = 0.5;
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 * keep green:((rgb >> 8) & 0xff) / 255.0 * keep blue:(rgb & 0xff) / 255.0 * keep alpha:1];
}

/* the blend behind the photo, the text over it, the action cards as veils with the same ink, and the emoji that tiles the ground */
- (void)showBackdropCenter:(uint32_t)center edge:(uint32_t)edge pattern:(uint32_t)pattern text:(uint32_t)text document:(long long)document {
    if (!_backdrop) {
        _backdrop = [[NoshiProfileBackdropView alloc] init];
        [_head insertSubview:_backdrop atIndex:0];
    }
    _backdrop.centerColor = NoshiColorOfRGB(center);
    _backdrop.edgeColor = NoshiColorOfRGB(edge);
    _backdrop.patternColor = NoshiColorOfRGB(pattern);
    _music.patternColor = NoshiColorOfRGB(pattern);
    _backdrop.photoRadius = AVATAR / 2;
    /* the bar over the ground is clear, which makes it the ground's continuation, and darkens with the scroll */
    self.barTint = NoshiDarkenedBackdrop(edge);
    UIColor *ink = NoshiColorOfRGB(text);
    [_cardInk release];
    _cardInk = [ink retain];
    _name.textColor = ink;
    _status.plainColor = [ink colorWithAlphaComponent:0.78f];
    _status.activeColor = ink;
    for (NoshiUserAction *action in [NSArray arrayWithObjects:_messageAction, _soundAction, _callAction, _videoAction, nil]) {
        [action setInk:ink];
        [action setGround:NoshiColorOfRGB(edge)];
    }
    if (document > 0) {
        NoshiWeakReference *weak = _weak;
        NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:document]], self.session, self.media, ^{
            [(NoshiUserProfileController *)weak.target showPatternOfDocument:document];
        });
        [self showPatternOfDocument:document];
    }
    [self.view setNeedsLayout];
    [_name setNeedsDisplay];
}

- (void)showPatternOfDocument:(long long)document {
    UIImage *picture = [NoshiCustomEmoji imageForDocument:document];
    if (!picture) return;
    _backdrop.patternImage = picture;
    _music.patternImage = picture;
}

- (void)showFull {
    NoshiFullUser *user = _fullUser;
    [_tabs setCommonChatsCount:user.commonChats];
    _ratingBadge.hidden = !user.hasRating;
    _ratingBadge.level = user.rating.level;
    _ratingBadge.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)user.rating.level];
    [self applyBackdropOfPerson:user.person];
    if (user.person.name.length) {
        [self showName:user.person.name emojiStatus:user.person.emojiStatus premium:user.person.premium];
    }
    NSString *birthday = @"";
    if (user.hasBirthday) {
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        parts.day = user.birthdayDay;
        parts.month = user.birthdayMonth;
        parts.year = user.birthdayYear > 0 ? user.birthdayYear : 2000;
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateFormat = user.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
        if (date) birthday = [formatter stringFromDate:date];
    }
    NoshiPerson *person = user.person;
    NSMutableArray *infoRows = [NSMutableArray arrayWithObjects:
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.phone", nil), NoshiPhoneDisplay(person.phone), nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.about", nil), user.about ? user.about : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.username", nil), person.username.length ? [@"@" stringByAppendingString:person.username] : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"contact.note.caption", nil), user.note ? user.note : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.birthday", nil), birthday, nil], nil];
    [infoRows addObjectsFromArray:NoshiIdentityRows(person.userId, person.photo)];
    [_info setRows:infoRows];
    /* the line under the name tells that the photo is the person's own pick once the profile says so */
    [self refreshStatus];
    _channelCard.hidden = user.channel == nil;
    if (user.channel) [_channelCard configureWithChannel:user.channel avatars:self.avatars];
    /* the saved messages are the account itself, and the track of its profile has no place in them: exteraGram shows it on the own profile only */
    _music.savedTrack = _dialog.saved ? nil : user.music;
    _callButton.hidden = ![self canCallPerson];
    [self refreshMenu];
    [self.view setNeedsLayout];
}

- (void)giftsChanged {
    /* folders filter the grid, not the gifts pinned around the photo */
    if (!_feed.folderId && !_feed.errorName) [_pinnedGifts setGifts:_feed.items];
    [self feedChanged];
}

- (void)feedChanged {
    /* the gifts show under the tabs only while the Gifts tab is chosen; the other tabs bring their own lists */
    BOOL gifts = _tabs.selectedTab == 0;
    [_grid setTiles:gifts ? _feed.tiles : [NSArray array]];
    BOOL any = _feed.items.count > 0;
    NSString *text = @"";
    if (gifts && _feed.loaded && !any) text = NSLocalizedString(@"gifts.empty", nil);
    if (![_empty.text isEqualToString:text]) _empty.text = text;
    [self.view setNeedsLayout];
}

- (void)giftGridReachedEnd:(NoshiGiftGridView *)grid {
    (void)grid;
    NoshiWeakReference *me = _weak;
    [_feed loadMore:^{ [(NoshiUserProfileController *)me.target giftsChanged]; }];
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

#pragma mark tabs

- (void)groupTabsDidResize:(NoshiGroupTabsView *)tabs {
    (void)tabs;
    [self.view setNeedsLayout];
}

- (void)groupTabsDidChooseTab:(NoshiGroupTabsView *)tabs {
    (void)tabs;
    [self feedChanged];
}

- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenPerson:(NoshiPerson *)person {
    (void)tabs;
    (void)person;
}

/* a group in common opens its chat */
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenDialog:(NoshiDialog *)dialog {
    (void)tabs;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:dialog avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

/* a file or a link opens the chat at its message */
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMessage:(NoshiMessage *)message {
    (void)tabs;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    chat.startMessageId = message.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}

/* a picture or video opens in the viewer, as in the chat, and not the chat at the place where it was sent */
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

#pragma mark layout

- (void)layoutHead {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;
    CGFloat contentWidth = MIN(width - 32, 460);
    CGFloat x = (width - contentWidth) / 2;
    CGFloat wideHeight = _heroOpen ? _heroHeight : 0;
    /* the photo reaches up under the bar and the status bar: its frame begins above the head by the inset of the list */
    if (_hero) _hero.frame = _heroOpen ? CGRectMake(0, -_grid.topInset, width, _grid.topInset + wideHeight) : _heroCircle;
    _avatar.frame = CGRectMake(15, 16, AVATAR, AVATAR);
    CGFloat outset = [NoshiStoryRing outset];
    _storyRing.frame = CGRectInset(_avatar.frame, -outset, -outset);
    /* the name and the status stand beside the photo, as a block in the middle of the head; the key of a call takes the right end */
    BOOL call = !_callButton.hidden;
    CGFloat textWidth = width - NAME_X - 14 - (call ? 50 : 0);
    _name.font = NoshiFontMedium(20);
    CGFloat nameHeight = MAX(24, ceil([_name sizeThatFits:CGSizeMake(textWidth, 200)].height));
    CGFloat block = nameHeight + 4 + 20;
    CGFloat headHeight = MAX(HEAD_HEIGHT, block + 32);
    CGFloat nameY = floor((headHeight - block) / 2);
    _name.frame = CGRectMake(NAME_X, nameY, textWidth, nameHeight);
    [self placeStatusAnimation];
    CGFloat badge = _ratingBadge.hidden ? 0 : 26;
    _ratingBadge.frame = CGRectMake(NAME_X, nameY + nameHeight + 4, 22, 20);
    _status.frame = CGRectMake(NAME_X + badge, nameY + nameHeight + 4, textWidth - badge, 20);
    _callButton.frame = CGRectMake(width - 57, floor((headHeight - 44) / 2), 44, 44);
    _headPanel.frame = CGRectMake(0, 0, width, headHeight);
    NoshiFitInfoGroupLines(_headPanel, NO);
    /* a collectible ground shows through the head, which is white otherwise */
    _headPanel.backgroundColor = _backdrop ? [UIColor clearColor] : NoshiColorCard();
    _pinnedGifts.frame = CGRectMake(0, 0, width, headHeight);
    _pinnedGifts.focus = CGPointMake(CGRectGetMidX(_avatar.frame), CGRectGetMidY(_avatar.frame));
    _pinnedGifts.hidden = _heroOpen;
    if (_backdrop) {
        CGFloat above = 600;
        _backdropBottom = _heroOpen ? wideHeight : headHeight;
        _backdrop.frame = CGRectMake(0, -above, width, above + _backdropBottom);
        _backdrop.focus = CGPointMake(CGRectGetMidX(_avatar.frame), above + CGRectGetMidY(_avatar.frame));
    }
    CGFloat y = (_heroOpen ? MAX(wideHeight, headHeight) : headHeight) + SECTION_GAP;
    _musicGroup.hidden = !_music.hasContent;
    if (_music.hasContent) {
        CGFloat pillHeight = [NoshiMusicPill height];
        _music.frame = CGRectMake(0, 0, width, pillHeight);
        _musicGroup.frame = CGRectMake(0, y, width, pillHeight);
        NoshiFitInfoGroupLines(_musicGroup, YES);
        y += pillHeight + SECTION_GAP;
    }
    if (!_info.hidden) {
        CGFloat height = [_info heightForWidth:width];
        _info.frame = CGRectMake(0, y, width, height);
        y += height + SECTION_GAP;
    }
    /* send a message, a video call while a call can be made, and the stories while the person has some */
    NSMutableArray *actions = [NSMutableArray arrayWithObject:_messageRow];
    if (call) [actions addObject:_videoRow];
    if (_storyPeer) [actions addObject:_storiesRow];
    y += NoshiLayoutInfoGroup(_actionsGroup, actions, y, width) + SECTION_GAP;
    y += NoshiLayoutInfoGroup(_soundGroup, [NSArray arrayWithObject:_soundRow], y, width) + SECTION_GAP;
    if (!_channelCard.hidden) {
        _channelCard.frame = CGRectMake(x, y, contentWidth, [NoshiChannelCard height]);
        y += [NoshiChannelCard height] + SECTION_GAP;
    }
    CGFloat tabsHeight = [_tabs heightForWidth:width];
    _tabs.frame = CGRectMake(0, y, width, tabsHeight);
    y += tabsHeight + GAP;
    CGFloat folders = _tabs.selectedTab == 0 ? [_folderBar height] : 0;
    _folderBar.hidden = folders == 0;
    _folderBar.frame = CGRectMake(x, y - GAP, contentWidth, folders);
    if (folders) y += folders;
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
    /* the list runs under the bar when the head has a ground of its own, which then shows through the clear bar; the bar's height is the list's top inset */
    BOOL underBar = _heroUnderBar;
    [_grid setFrame:underBar ? CGRectMake(body.origin.x, 0, body.size.width, CGRectGetMaxY(body)) : body topInset:underBar ? body.origin.y : 0];
    _toast.frame = CGRectMake(CGRectGetMidX(body) - 80, body.origin.y + 12, 160, 28);
    [self layoutHead];
}

/* the bar fills once the head has moved a little under it, and clears again at the top */
- (void)giftGrid:(NoshiGiftGridView *)grid didScrollToOffset:(CGFloat)offset {
    (void)grid;
    [_tabs hostDidScroll];
    [self heroFollowsPull:-(offset + _grid.topInset)];
}

#pragma mark actions

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

#pragma mark menu

typedef enum { NoshiUserMenuCopyLink, NoshiUserMenuGift, NoshiUserMenuNotifications, NoshiUserMenuReport, NoshiUserMenuEditContact, NoshiUserMenuSharing, NoshiUserMenuBlock } NoshiUserMenuEntry;

- (BOOL)canGift {
    return _dialog.kind == NOSHI_DIALOG_USER && !_dialog.saved;
}

/* the calls go to a person, not to a bot; the profile that was opened from a mention learns that it is a bot when the full user comes in */
- (BOOL)canCallPerson {
    return [self canGift] && !_fullUser.person.bot && _dialog.peerId != NOSHI_TELEGRAM_SERVICE_USER_ID;
}

- (NSString *)username {
    return _fullUser.person.username.length ? _fullUser.person.username : nil;
}

/* the profile of this account, reached by a mention or a link rather than by the saved messages: the server refuses to restrict, block or report oneself (PEER_ID_INVALID) */
- (BOOL)isOwnAccount {
    NoshiPerson *own = [self.session ownPerson];
    return _dialog.saved || (own && _dialog.peerKind == 1 && _dialog.peerId == own.userId);
}

/* the saved messages are the account itself, which nobody reports */
- (BOOL)canReport {
    return ![self isOwnAccount];
}

/* the three dots only show while the menu has something to offer */
- (void)refreshMenu {
    if (![self canGift] && ![self username] && ![self canReport] && !_dialog.saved) {
        [self setActionSymbol:NoshiSymbolEllipsis label:nil handler:nil];
        return;
    }
    NoshiWeakReference *me = _weak;
    [self setActionSymbol:NoshiSymbolEllipsis label:NSLocalizedString(@"profile.more", nil)
                  handler:^{ [(NoshiUserProfileController *)me.target showMenu]; }];
}

/* a block is asked about first, since it cuts the person off; letting them back in is done at once, as the button of the chat does it */
- (void)toggleBlock {
    BOOL block = !_fullUser.blocked;
    NoshiWeakReference *me = _weak;
    void (^apply)(void) = ^{
        NoshiUserProfileController *profile = me.target;
        if (!profile) return;
        [profile.session setBlocked:block kind:profile->_dialog.peerKind identifier:profile->_dialog.peerId hash:profile->_dialog.peerHash completion:^(NSString *errorName) {
            NoshiUserProfileController *current = me.target;
            if (errorName) {
                NSLog(@"noshigram: the block was not changed: %@", errorName);
                NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"profile.block.error", nil), errorName]);
                return;
            }
            /* the profile is read again, and brings the state the server keeps now */
            [current load];
        }];
    };
    if (!block) { apply(); return; }
    NoshiConfirm(nil, [NSString stringWithFormat:NSLocalizedString(@"profile.block.confirm", nil), _dialog.title], NSLocalizedString(@"profile.block", nil), apply);
}

/* the contact is edited on a screen of its own: the name, the note under the username and the photo */
- (void)askContactName {
    NoshiPerson *person = _fullUser.person;
    if (!person) return;
    NoshiWeakReference *me = _weak;
    NoshiContactEditController *edit = [[[NoshiContactEditController alloc] initWithSession:self.session person:person fullUser:_fullUser avatars:self.avatars media:self.media] autorelease];
    /* the profile is read again, and brings the name, the note and the photo the server keeps now */
    edit.changedHandler = ^{ [(NoshiUserProfileController *)me.target load]; };
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)showMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *entries = [NSMutableArray array];
    NoshiSymbol symbols[7];
    if (_fullUser && [self canGift] && ![self isOwnAccount] && !_fullUser.person.bot && _fullUser.person.accessHash && _dialog.peerId != NOSHI_TELEGRAM_SERVICE_USER_ID) {
        symbols[titles.count] = NoshiSymbolLock;
        [titles addObject:NSLocalizedString(_fullUser.sharingRestricted ? @"chat.sharing.allow" : @"chat.sharing.disable", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuSharing]];
    }
    /* a person the account can rename: a user with a hash, once the profile is in */
    if ([self canGift] && ![self isOwnAccount] && _fullUser.person.accessHash && !_fullUser.person.bot) {
        symbols[titles.count] = NoshiSymbolCompose;
        [titles addObject:NSLocalizedString(_fullUser.person.contact ? @"profile.contact.edit" : @"profile.contact.add", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuEditContact]];
    }
    if ([self username]) {
        symbols[titles.count] = NoshiSymbolLink;
        [titles addObject:NSLocalizedString(@"profile.qr.copy", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuCopyLink]];
    }
    if ([self canGift]) {
        symbols[titles.count] = NoshiSymbolGift;
        [titles addObject:NSLocalizedString(@"gifts.send", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuGift]];
    }
    if (!_dialog.saved) {
        symbols[titles.count] = NoshiSymbolBell;
        [titles addObject:NSLocalizedString(@"notif.chat.header", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuNotifications]];
    }
    /* a person can be blocked or let back in, as in the official clients; not oneself, and not the service account */
    if (_fullUser && [self canGift] && ![self isOwnAccount] && _fullUser.person.accessHash && _dialog.peerId != NOSHI_TELEGRAM_SERVICE_USER_ID) {
        symbols[titles.count] = NoshiSymbolBlock;
        [titles addObject:NSLocalizedString(_fullUser.blocked ? @"profile.unblock" : @"profile.block", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuBlock]];
    }
    if ([self canReport]) {
        symbols[titles.count] = NoshiSymbolReport;
        [titles addObject:NSLocalizedString(@"report.title", nil)];
        [entries addObject:[NSNumber numberWithInt:NoshiUserMenuReport]];
    }
    if (!titles.count) return;
    NoshiWeakReference *me = _weak;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        NoshiUserProfileController *profile = me.target;
        if (!profile || index >= entries.count) return;
        switch ([[entries objectAtIndex:index] intValue]) {
        case NoshiUserMenuSharing: {
            BOOL restricted = !profile->_fullUser.sharingRestricted;
            NoshiConfirm(nil, NSLocalizedString(restricted ? @"chat.sharing.disable.confirm" : @"chat.sharing.allow.confirm", nil),
                           NSLocalizedString(restricted ? @"chat.sharing.disable" : @"chat.sharing.allow", nil), ^{
                NoshiUserProfileController *owner = me.target;
                if (!owner) return;
                [owner.session setSharingRestricted:restricted ofDialog:owner->_dialog requestId:0 completion:^(NSString *errorName) {
                    NoshiUserProfileController *current = me.target;
                    if (errorName) NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.sharing.error", nil), errorName]);
                    else {
                        NoshiShowNotice(nil, NSLocalizedString(@"chat.sharing.sent", nil));
                        [current load];
                    }
                }];
            });
            break;
        }
        case NoshiUserMenuEditContact: [profile askContactName]; break;
        case NoshiUserMenuBlock: [profile toggleBlock]; break;
        case NoshiUserMenuCopyLink: [profile copyLink]; break;
        case NoshiUserMenuGift: [profile sendGift]; break;
        case NoshiUserMenuNotifications:
            [profile.navigationController pushViewController:[[[NoshiNotificationsChatController alloc] initWithSession:profile.session media:profile.media peerKind:profile->_dialog.peerKind
                                                                                                                  peerId:profile->_dialog.peerId peerHash:profile->_dialog.peerHash channel:NO
                                                                                                                   topic:0 title:profile->_dialog.title] autorelease] animated:YES];
            break;
        case NoshiUserMenuReport: [NoshiReportFlow startForDialog:profile->_dialog session:profile.session host:profile done:nil]; break;
        }
    }] autorelease];
    [menu showInView:self.view anchor:[self actionSymbolAnchor]];
}

/* the chat the profile was opened from when it is right below, a new one otherwise */
- (void)openMessages {
    NoshiProfileShowChat(self, self.session, _dialog, self.avatars, self.media, _stickers);
}

- (void)startCall {
    [self.session startCallToDialog:_dialog];
}

- (void)startVideoCall {
    [self.session startVideoCallToDialog:_dialog];
}

- (void)refreshSound {
    [_soundAction setSymbol:_muted ? NoshiSymbolProfileUnmute : NoshiSymbolProfileMute
                      title:NSLocalizedString(@"profile.action.sound", nil)];
    _soundRow.value = NSLocalizedString(_muted ? @"profile.row.notifications.off" : @"profile.row.notifications.on", nil);
}

- (void)toggleMute {
    if (_muteBusy) return;
    _muteBusy = YES;
    BOOL mute = !_muted;
    NoshiWeakReference *me = _weak;
    [self retain];
    [self.session performAction:mute ? NoshiChatCommandMute : NoshiChatCommandUnmute onDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiUserProfileController *profile = me.target;
        if (!profile) return;
        profile->_muteBusy = NO;
        if (errorName) {
            [profile toast:NoshiGiftErrorText(errorName)];
            return;
        }
        profile->_muted = mute;
        [profile refreshSound];
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
    }];
}

- (void)copyLink {
    NSString *username = [self username];
    if (!username) return;
    [UIPasteboard generalPasteboard].string = [@"https://t.me/" stringByAppendingString:username];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

- (void)openCode {
    NoshiPerson *person = _fullUser.person;
    if (!person) return;
    NoshiProfileQrController *code = [[[NoshiProfileQrController alloc] initWithSession:self.session person:person avatars:self.avatars
                                                                                      media:self.media] autorelease];
    [self.navigationController pushViewController:code animated:YES];
}

- (void)sendGift {
    NoshiGiftCatalogController *catalog = [[[NoshiGiftCatalogController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars
                                                                                              media:self.media] autorelease];
    NoshiWeakReference *me = _weak;
    catalog.sentHandler = ^{
        NoshiUserProfileController *profile = me.target;
        if (profile) [profile->_feed reload:^{ [(NoshiUserProfileController *)me.target giftsChanged]; }];
    };
    [self.navigationController pushViewController:catalog animated:YES];
}

/* a tap on the photo opens it wide inside the head: the circle grows to the width of the screen, the cards of the profile ride up over its lower edge, and everything under it moves down; the head
   scrolls with the rest of the screen */
- (void)openHero {
    if (_hero || _heroMoving) return;
    /* with no photo there is nothing to open wide, and the viewer would be a black screen; a person with only the public photo has one to show */
    if (!_dialog.photo && !_fullUser.publicPhoto) return;
    NoshiProfileHeroView *hero = [[[NoshiProfileHeroView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media] autorelease];
    /* the public photo is the last page of the wide photo, with the circle that leads to it and back; it is set again when the full profile arrives after the photo was opened */
    hero.publicPhoto = _fullUser.publicPhoto;
    hero.name.text = _name.text;
    hero.name.entities = _name.entities;
    hero.status.text = _status.text;
    [hero setRatingLevel:_ratingBadge.hidden ? 0 : _ratingBadge.level target:self action:@selector(openRating)];
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
    NSArray *cards = [NSArray arrayWithObjects:_messageAction, _soundAction, _callAction, _videoAction, nil];
    for (NoshiUserAction *card in cards) [_head bringSubviewToFront:card];
    BOOL motion = !NoshiReduceMotionEnabled();
    [hero animateCornerTo:0 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        for (NoshiUserAction *card in cards) {
            [card setInk:[UIColor whiteColor]];
            [card setBlurred:YES];
        }
        _name.alpha = 0;
        _statusAnimation.alpha = 0;
        _status.alpha = 0;
        _ratingBadge.alpha = 0;
        [self setBarOverPhoto:YES];
        [self layoutHead];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        _avatar.hidden = YES;
        /* the wide photo draws the name with its own still status, and the moving one under it would play over the picture */
        [_statusAnimation setPlaying:NO];
        [_hero finishOpen];
        if (_viewerWanted) {
            _viewerWanted = NO;
            [self openAvatarViewer];
        }
    }];
}

/* the photos of the person on the whole screen; the arrow of the viewer comes back to the wide photo, which stays open under it */
/* a long pull goes through the whole opening of the wide photo in one drag: the part that came while it opened is kept, or the photos would ask for a second pull */
- (BOOL)holdsPullWhileOpening:(CGFloat)pull {
    if (!_heroMoving) return NO;
    if (_heroOpen && pull > HERO_VIEW_PULL) _viewerWanted = YES;
    return YES;
}

/* the screen's own swipes: a pull down opens the photo wide, a longer one opens the photos, and scrolling up closes the wide photo; the head stays still while it changes */
- (void)heroFollowsPull:(CGFloat)pull {
    if ([self holdsPullWhileOpening:pull]) return;
    if (!_hero) {
        if (pull > HERO_OPEN_PULL) [self openHero];
    } else if (_heroOpen) {
        if (pull > HERO_VIEW_PULL) [self openAvatarViewer];
        else if (-pull > HERO_FOLD_SCROLL) [self closeHero];
    }
}

- (void)openAvatarViewer {
    if (!_hero || !_heroOpen || _heroMoving || self.presentedViewController) return;
    NoshiAvatarViewer *viewer = [[[NoshiAvatarViewer alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media] autorelease];
    viewer.publicPhoto = _fullUser.publicPhoto;
    viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)closeHero {
    if (!_hero || !_heroOpen || _heroMoving) return;
    _heroMoving = YES;
    _heroOpen = NO;
    _avatar.hidden = NO;
    [_hero beginClose];
    [_statusAnimation setPlaying:self.view.window != nil];
    NSArray *cards = [NSArray arrayWithObjects:_messageAction, _soundAction, _callAction, _videoAction, nil];
    BOOL motion = !NoshiReduceMotionEnabled();
    [_hero animateCornerTo:_heroCircle.size.width / 2 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        for (NoshiUserAction *card in cards) {
            [card setBlurred:NO];
            [card setInk:_cardInk];
        }
        _name.alpha = 1;
        _statusAnimation.alpha = 1;
        _status.alpha = 1;
        _ratingBadge.alpha = 1;
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

- (void)openStories {
    if (!_storyPeer) return;
    /* a second tap while a viewer is up or rising would stack another viewer on the first, and both would play the same story's sound */
    if (self.presentedViewController) return;
    NoshiStoryViewerController *viewer = [[[NoshiStoryViewerController alloc] initWithSession:self.session peers:[NSArray arrayWithObject:_storyPeer] index:0
                                                                                          avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)musicContentChanged {
    [self layoutHead];
    [self.view setNeedsLayout];
}

- (void)openMusic {
    NoshiMusicListController *list = [[[NoshiMusicListController alloc] initWithSession:self.session dialog:_dialog first:_fullUser.music
                                                                                    avatars:self.avatars media:self.media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openRating {
    NoshiShowRating(self.view.window, _fullUser);
}

- (void)openChannel {
    NoshiPersonalChannel *channel = _fullUser.channel;
    if (!channel) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:channel.dialog avatars:self.avatars media:self.media
                                                                         stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

@end
