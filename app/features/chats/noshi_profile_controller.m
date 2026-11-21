#import "noshi_developers.h"
#import "noshi_alert_view.h"
#import "noshi_emoji_label.h"
#import "noshi_gift_folder_bar.h"
#import "noshi_profile_backdrop_view.h"
#import "noshi_profile_colors.h"
#import "noshi_custom_emoji.h"
#import "noshi_lite_mode.h"
#import "noshi_image_decoder.h"
#import "noshi_lottie_view.h"
#import "noshi_animation.h"
#import "noshi_text_filter.h"
#import "noshi_profile_controller.h"
#import "noshi_profile_identity_view.h"
#import "noshi_chat_settings.h"
#import "noshi_name_badge.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_alert.h"
#import "noshi_accounts.h"
#import "noshi_avatar_viewer.h"
#import "noshi_profile_hero_view.h"
#import "noshi_channel_card.h"
#import "noshi_chat_controller.h"
#import "noshi_info_card_view.h"
#import "noshi_profile_qr_controller.h"
#import "noshi_row_icon.h"
#import "noshi_contact_picker_controller.h"
#import "noshi_avatar_viewer.h"
#import "noshi_dialog.h"
#import "noshi_gift_catalog_controller.h"
#import "noshi_gift_detail_controller.h"
#import "noshi_gift_grid_view.h"
#import "noshi_person.h"
#import "noshi_popup_menu.h"
#import "noshi_music_list_controller.h"
#import "noshi_music_pill.h"
#import "noshi_pill_tabs_view.h"
#import "noshi_platform.h"
#import "noshi_profile_edit_controller.h"
#import "noshi_profile_feed.h"
#import "noshi_rating_view.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_session_profile.h"
#import "noshi_sheet.h"
#import "noshi_story_viewer_controller.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_wave_background_view.h"
#import "noshi_weak_reference.h"

#define BAR_HEIGHT 44.0
#define ACTION_HEIGHT 70.0
#define ACTION_GAP 8.0
#define INFO_ROW 62.0
#define GAP 14.0
#define SEND_HEIGHT 48.0

/* the edit action under the profile */
@interface NoshiProfileAction : UIControl {
    UIImageView *_icon;
    UILabel *_caption;
    NoshiSymbol _symbol;
    BOOL _onPhoto;
    UIColor *_ink;
}
- (id)initWithSymbol:(NoshiSymbol)symbol title:(NSString *)title;
/* the card stands on the wide photo: a dark veil for its plate and white for the symbol and the word; NO puts the colors of the screen back */
- (void)setOnPhoto:(BOOL)onPhoto;
/* the card on the colored ground of a collectible profile: a dark veil for the plate and the ink of the profile for the symbol and the word; nil puts the colors of the screen back */
- (void)setInk:(UIColor *)ink;
@end

@implementation NoshiProfileAction

- (id)initWithSymbol:(NoshiSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    NoshiAttachBounce(self, 0.06);
    self.backgroundColor = NoshiColorCard();
    self.layer.cornerRadius = 14;
    _symbol = symbol;
    _icon = [[UIImageView alloc] initWithImage:NoshiSymbolImage(symbol, 24, NoshiColorAccent())];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textAlignment = NoshiTextAlignmentCenter;
    _caption.font = NoshiFontMedium(13);
    _caption.textColor = NoshiColorTitle();
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.text = title;
    [self addSubview:_caption];
    self.accessibilityLabel = title;
    return self;
}

- (void)setOnPhoto:(BOOL)onPhoto {
    if (onPhoto == _onPhoto) return;
    _onPhoto = onPhoto;
    [self applyColors];
}

- (void)setInk:(UIColor *)ink {
    if (ink == _ink) return;
    [_ink release];
    _ink = [ink retain];
    [self applyColors];
}

/* the wide photo and the colored ground both want a veil and light ink, the plain screen the card colors */
- (void)applyColors {
    UIColor *ink = _onPhoto ? [UIColor whiteColor] : _ink;
    self.backgroundColor = ink ? [UIColor colorWithWhite:0 alpha:0.32f] : NoshiColorCard();
    _icon.image = NoshiSymbolImage(_symbol, 24, ink ? ink : NoshiColorAccent());
    _caption.textColor = ink ? ink : NoshiColorTitle();
}

- (void)dealloc {
    [_ink release];
    [_icon release];
    [_caption release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* a tall button, the icon over its word, as the three buttons under the photo are */
    if (size.height >= 60) {
        _icon.frame = CGRectMake(floor((size.width - 28) / 2), 12, 28, 28);
        _caption.frame = CGRectMake(4, 44, size.width - 8, 18);
        return;
    }
    CGFloat text = MIN(MAX(0, size.width - 52), ceil([_caption sizeThatFits:CGSizeMake(size.width, 24)].width));
    CGFloat left = floor((size.width - text - 28) / 2);
    _icon.frame = CGRectMake(left, (size.height - 22) / 2, 22, 22);
    _caption.frame = CGRectMake(left + 28, 0, text, size.height);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}

@end

@interface NoshiProfileController () <NoshiGiftGridDelegate, NoshiGiftFolderBarDelegate> {
    NoshiGiftFolderBar *_folderBar;
    NoshiSession *_session;
    CGFloat _bottomInset;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWaveBackgroundView *_backdrop;
    /* the colored ground behind the head when the account wears a collectible color or status, and the ink the head wears on it */
    NoshiProfileBackdropView *_ground;
    UIColor *_groundInk;
    /* the emoji status when it moves: drawn over the still picture the name already holds, at the place the name leaves for it */
    NoshiLottieView *_statusAnimation;
    long long _statusAnimationDocument;
    NSUInteger _statusAnimationToken;
    UIView *_bar;
    BOOL _barFilled;
    UILabel *_titleLabel;
    NoshiEmojiLabel *_barName;
    UILabel *_barStatus;
    NoshiGiftGridView *_grid;
    UIView *_head;
    NoshiProfileIdentityView *_identity;
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_name;
    UILabel *_status;
    NoshiRatingBadge *_ratingBadge;
    NoshiProfileAction *_editAction;
    NoshiProfileAction *_photoAction;
    NoshiProfileHeroView *_hero;
    NoshiProfileAction *_settingsAction;
    NoshiInfoCardView *_info;
    UIActivityIndicatorView *_spinner;
    NoshiPillTabsView *_tabs;
    UILabel *_empty;
    UIButton *_send;
    UILabel *_toast;
    NoshiProfileFeed *_feeds[3];
    NSUInteger _tab;
    NoshiPerson *_person;
    NSString *_about;
    NoshiFullUser *_full;
    NoshiMusicPill *_music;
    NoshiChannelCard *_channelCard;
    UIButton *_qrButton;
    UIButton *_moreButton;
    UIImage *_starsImage;
    NoshiStickerLibrary *_stickerLibrary;
    NoshiWeakReference *_weak;
    CGFloat _headHeight;
    /* the photo opened wide in the head: the frame it was a circle in, the height it grows to, and whether it is open (a closing one is still in the head until its frame has shrunk) */
    CGRect _heroCircle;
    CGFloat _heroHeight;
    BOOL _heroOpen;
    BOOL _heroMoving;
    BOOL _viewerWanted;
    CGFloat _headWidth;
    BOOL _working;
    BOOL _uploading;
}
@end

@implementation NoshiProfileController

@synthesize delegate = _delegate;
@synthesize bottomInset = _bottomInset;
@synthesize avatars = _avatars;
@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _about = [@"" copy];
    return self;
}

/* a tap on the photo opens it wide inside the head: the circle grows to the width of the screen, the buttons ride up over its lower edge, and everything under it moves down; the head scrolls with
   the rest of the screen */
- (void)openHero {
    if (_hero || !_person || _heroMoving) return;
    /* with no photo there is nothing to open wide, and the viewer would be a black screen */
    if (!_person.photo && !_full.publicPhoto) return;
    NoshiProfileHeroView *hero = [[[NoshiProfileHeroView alloc] initWithSession:_session dialog:[NoshiDialog savedMessagesWithPerson:_person] avatars:_avatars media:_media] autorelease];
    hero.name.text = _name.text;
    hero.name.entities = _name.entities;
    hero.status.text = _status.text;
    hero.publicPhoto = _full.publicPhoto;
    [hero setRatingLevel:_ratingBadge.hidden ? 0 : _ratingBadge.level target:self action:@selector(openRating)];
    _heroCircle = [_identity convertRect:_avatar.frame toView:_head];
    _heroHeight = [NoshiProfileHeroView heightForWidth:_grid.bounds.size.width screenHeight:self.view.bounds.size.height];
    hero.frame = _heroCircle;
    hero.stripTop = NoshiLayoutInsets(self).top + 8;
    hero.layer.cornerRadius = _heroCircle.size.width / 2;
    [hero beginMove];
    [_head insertSubview:hero belowSubview:_photoAction];
    _hero = [hero retain];
    _heroOpen = YES;
    _heroMoving = YES;
    BOOL motion = !NoshiReduceMotionEnabled();
    [hero animateCornerTo:0 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        for (NoshiProfileAction *action in [NSArray arrayWithObjects:_photoAction, _editAction, _settingsAction, nil]) [action setOnPhoto:YES];
        _identity.alpha = 0;
        _statusAnimation.alpha = 0;
        _titleLabel.alpha = 0;
        [self layoutHead];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        _identity.hidden = YES;
        [_hero finishOpen];
        if (_viewerWanted) {
            _viewerWanted = NO;
            [self openAvatarViewer];
        }
    }];
}

/* another tab takes the screen: the photo shrinks back to its circle while the tab slides away, so it is not left wide when the person comes back */
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_statusAnimation setPlaying:NO];
    if (_heroOpen && !_heroMoving) [self closeHero];
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
    NoshiAvatarViewer *viewer = [[[NoshiAvatarViewer alloc] initWithSession:_session dialog:[NoshiDialog savedMessagesWithPerson:_person] avatars:_avatars media:_media] autorelease];
    viewer.title = _person.name;
    viewer.publicPhoto = _full.publicPhoto;
    viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)closeHero {
    if (!_hero || !_heroOpen || _heroMoving) return;
    _heroMoving = YES;
    _heroOpen = NO;
    _identity.hidden = NO;
    [_hero beginClose];
    BOOL motion = !NoshiReduceMotionEnabled();
    [_hero animateCornerTo:_heroCircle.size.width / 2 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        for (NoshiProfileAction *action in [NSArray arrayWithObjects:_photoAction, _editAction, _settingsAction, nil]) [action setOnPhoto:NO];
        _identity.alpha = 1;
        _statusAnimation.alpha = 1;
        _titleLabel.alpha = 1;
        [self layoutHead];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        [_hero removeFromSuperview];
        [_hero release];
        _hero = nil;
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiChatSettingsDidChangeNotification object:nil];
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_session release];
    [_avatars release];
    [_media release];
    [_stickerLibrary release];
    [_full release];
    [_music release];
    [_channelCard release];
    [_qrButton release];
    [_moreButton release];
    [_starsImage release];
    [_backdrop release];
    [_ground release];
    [_groundInk release];
    [_statusAnimation release];
    [_bar release];
    [_titleLabel release];
    [_barName release];
    [_barStatus release];
    [_grid release];
    [_head release];
    [_identity release];
    [_avatar release];
    [_name release];
    [_status release];
    [_ratingBadge release];
    [_editAction release];
    [_photoAction release];
    [_hero release];
    [_settingsAction release];
    for (int i = 0; i < 3; ++i) [_feeds[i] release];
    [_info release];
    [_spinner release];
    _folderBar.delegate = nil;
    [_folderBar release];
    [_tabs release];
    [_empty release];
    [_send release];
    [_toast release];
    [_person release];
    [_about release];
    [super dealloc];
}

static UILabel *NoshiProfileLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[NoshiWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.plain = YES;
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    _grid = [[NoshiGiftGridView alloc] initWithMedia:_media];
    _grid.avatars = _avatars;
    _grid.delegate = self;
    [root addSubview:_grid];

    _head = [[UIView alloc] init];
    _head.backgroundColor = [UIColor clearColor];
    /* the photo, the camera, the name and the line under it are the block that the settings screen shows too, so both lay out the same */
    _identity = [[NoshiProfileIdentityView alloc] init];
    [_identity.avatarHit addTarget:self action:@selector(openHero) forControlEvents:UIControlEventTouchUpInside];
    [_identity.badge addTarget:self action:@selector(choosePhoto) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_identity];
    _avatar = [_identity.avatar retain];
    _name = [_identity.name retain];
    _status = [_identity.line retain];
    _status.text = NSLocalizedString(@"profile.online", nil);
    _ratingBadge = [[NoshiRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    [_ratingBadge addTarget:self action:@selector(openRating) forControlEvents:UIControlEventTouchUpInside];
    [_identity addSubview:_ratingBadge];

    /* the photo is picked here, so the camera on the picture that the settings screen keeps is not drawn on this one */
    _identity.badge.hidden = YES;
    _photoAction = [[NoshiProfileAction alloc] initWithSymbol:NoshiSymbolCameraPlus title:NSLocalizedString(@"profile.choosephoto", nil)];
    [_photoAction addTarget:self action:@selector(choosePhoto) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_photoAction];
    _editAction = [[NoshiProfileAction alloc] initWithSymbol:NoshiSymbolCompose title:NSLocalizedString(@"profile.edit", nil)];
    [_editAction addTarget:self action:@selector(editProfile) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_editAction];
    _settingsAction = [[NoshiProfileAction alloc] initWithSymbol:NoshiSymbolGear title:NSLocalizedString(@"tab.settings", nil)];
    [_settingsAction addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_settingsAction];

    _music = [[NoshiMusicPill alloc] init];
    _music.media = self.media;
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    NoshiWeakReference *musicMe = _weak;
    _music.contentHandler = ^{ [(NoshiProfileController *)musicMe.target layoutHead]; };
    [_head addSubview:_music];

    _channelCard = [[NoshiChannelCard alloc] init];
    _channelCard.hidden = YES;
    [_channelCard addTarget:self action:@selector(openChannel) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_channelCard];

    _info = [[NoshiInfoCardView alloc] init];
    NoshiWeakReference *infoMe = _weak;
    _info.copyHandler = ^{ [(NoshiProfileController *)infoMe.target toast:NSLocalizedString(@"profile.copied", nil)]; };
    [_head addSubview:_info];

    _tabs = [[NoshiPillTabsView alloc] initWithTitles:[NSArray arrayWithObjects:NSLocalizedString(@"profile.tab.stories", nil),
                                                         NSLocalizedString(@"profile.tab.archive", nil), NSLocalizedString(@"gifts.title", nil), nil]];
    NoshiWeakReference *me = _weak;
    _tabs.changeHandler = ^(NSUInteger index) { [(NoshiProfileController *)me.target selectTab:index]; };
    [_head addSubview:_tabs];
    _empty = NoshiProfileLabel(NoshiColorSecondary(), NoshiFontRegular(15), NoshiTextAlignmentCenter);
    _empty.numberOfLines = 0;
    [_head addSubview:_empty];
    _grid.headerView = _head;

    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [NoshiColorScreen() colorWithAlphaComponent:0.94];
    _bar.alpha = 0;
    [root addSubview:_bar];
    _titleLabel = NoshiProfileLabel(NoshiColorTitle(), NoshiFontBold(NoshiIsPad() ? 24 : 20), NoshiTextAlignmentCenter);
    _titleLabel.text = NSLocalizedString(@"tab.profile", nil);
    [root addSubview:_titleLabel];
    _barName = [[NoshiEmojiLabel alloc] init];
    _barName.dropsUndrawable = YES;
    _barName.textColor = NoshiColorTitle();
    _barName.font = NoshiFontSemibold(17);
    _barName.textAlignment = NoshiTextAlignmentCenter;
    _barName.alpha = 0;
    [root addSubview:_barName];
    _barStatus = NoshiProfileLabel(NoshiColorSecondary(), NoshiFontRegular(12), NoshiTextAlignmentCenter);
    _barStatus.text = NSLocalizedString(@"profile.online", nil);
    _barStatus.alpha = 0;
    [root addSubview:_barStatus];

    _qrButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_qrButton setImage:NoshiSymbolImage(NoshiSymbolQr, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    [_qrButton addTarget:self action:@selector(openQr) forControlEvents:UIControlEventTouchUpInside];
    _qrButton.accessibilityLabel = NSLocalizedString(@"profile.qr", nil);
    [root addSubview:_qrButton];

    /* the menu only has the link to copy, so the dots wait for a username */
    _moreButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_moreButton setImage:NoshiSymbolImage(NoshiSymbolEllipsis, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    [_moreButton addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    _moreButton.accessibilityLabel = NSLocalizedString(@"profile.more", nil);
    [root addSubview:_moreButton];
    /* the sign out runs behind the dots, so its wait is shown in their place */
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:NoshiThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];

    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _send.backgroundColor = NoshiColorAccent();
    _send.layer.cornerRadius = SEND_HEIGHT / 2;
    _send.titleLabel.font = NoshiFontSemibold(17);
    [_send setTitle:[@"  " stringByAppendingString:NSLocalizedString(@"profile.sendgifts", nil)] forState:UIControlStateNormal];
    [_send setImage:NoshiSymbolImage(NoshiSymbolGift, 20, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_send setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_send addTarget:self action:@selector(sendGifts) forControlEvents:UIControlEventTouchUpInside];
    _send.hidden = YES;
    [root addSubview:_send];
    _toast = NoshiProfileLabel([UIColor whiteColor], NoshiFontSemibold(14), NoshiTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged) name:NoshiChatSettingsDidChangeNotification object:nil];
    [self refreshOwnStatus];
    [self loadProfile];
    [self selectTab:0];
}

- (void)chatSettingsChanged {
    [self refreshOwnStatus];
    if (_person) [self refreshProfile];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshOwnStatus];
    /* a story seen or a gift hidden while away shows on coming back */
    if (_person) [self refreshCurrentFeed];
    /* the public photo is set and removed on the privacy page, so the full profile is asked again to show it without a reopen */
    [self loadFull];
}

- (void)refreshOwnStatus {
    NSString *text = NSLocalizedString(@"profile.online", nil);
    _status.text = text;
    _barStatus.text = text;
    [self layoutHead];
}

#pragma mark data

- (void)loadProfile {
    /* the profile of the last time draws at once, and the answer corrects it */
    if (!_person && [_session ownPerson]) {
        _person = [[_session ownPerson] retain];
        [self refreshProfile];
    }
    [self retain];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items) {
            NSLog(@"noshigram: profile did not load: %@", errorName);
            return;
        }
        [_person release];
        _person = [[items objectAtIndex:0] retain];
        NoshiAccountKeepPhotoOfPerson(_person, _avatars);
        [self refreshProfile];
        [self refreshCurrentFeed];
        [self loadFull];
    }];
    [self retain];
    [_session loadStarsBalance:^(long long stars, NSString *errorName) {
        [self autorelease];
        if (errorName) {
            NSLog(@"noshigram: star balance not loaded: %@", errorName);
            return;
        }
        [_starsImage release];
        _starsImage = [NoshiStarsImage(nil, stars, NoshiFontSemibold(17), NoshiColorTitle()) retain];
        [self refreshProfile];
    }];
}

/* the bio, the birthday and the personal channel, which come with the full profile */
- (void)loadFull {
    if (!_person) return;
    [self retain];
    [_session loadFullUserOfDialog:[NoshiDialog savedMessagesWithPerson:_person] completion:^(NoshiFullUser *user, NSString *errorName) {
        [self autorelease];
        if (!user) {
            NSLog(@"noshigram: full profile did not load: %@", errorName);
            return;
        }
        [_full release];
        _full = [user retain];
        [_about release];
        _about = [user.about copy];
        [self refreshProfile];
    }];
}

- (void)refreshProfile {
    _hero.publicPhoto = _full.publicPhoto;
    _ratingBadge.hidden = !_full.hasRating;
    if (_full.hasRating) {
        _ratingBadge.level = _full.rating.level;
        _ratingBadge.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)_full.rating.level];
    }
    /* the account's own mark: the status it chose, else the Premium star, which a switch of Noshigram can also give */
    long long badge = NoshiBadgeDocument(_person.emojiStatus, NoshiPremiumEffective(_person.premium));
    _identity.userId = _person.userId;
    [_identity setName:_person.name badge:badge developer:NoshiPersonIsDeveloper(_person)];
    [self animateStatus:badge == _person.emojiStatus ? _person.emojiStatus : 0];
    [self applyBackdropOfPerson:_person];
    if (_person.emojiStatus) {
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:_identity];
        NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:_person.emojiStatus]], _session, _media, ^{ [(NoshiProfileIdentityView *)weak.target redrawName]; });
    }
    _barName.text = _person.name;
    _avatar.initials = _person.initials;
    _avatar.deleted = _person.deleted;
    _avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [_avatar setPhoto:_person.photo cache:_avatars];
    NSString *birthday = @"";
    if (_full.hasBirthday) {
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        parts.day = _full.birthdayDay;
        parts.month = _full.birthdayMonth;
        parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
        if (date) birthday = [formatter stringFromDate:date];
    }
    NSMutableArray *infoRows = [NSMutableArray arrayWithObjects:
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.phone", nil), NoshiOwnPhoneText(_person.phone), nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.about", nil), _about ? _about : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.username", nil), _person.username.length ? [@"@" stringByAppendingString:_person.username] : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.birthday", nil), birthday, nil], nil];
    [infoRows addObjectsFromArray:NoshiIdentityRows(_person.userId, _person.photo)];
    [_info setRows:infoRows];
    [_info setStarsBalance:_starsImage caption:NSLocalizedString(@"profile.stars", nil)];
    _music.savedTrack = _full.music;
    [self refreshChannelCard];
    [self layoutHead];
}

/* a status that is an animation (tgs, or a video sticker) is fetched once and plays in place of its still picture; a plain one stays as it is drawn. The same
   status again only puts the animation back at the place the name now leaves for it */
- (void)animateStatus:(long long)document {
    if (document && document == _statusAnimationDocument) {
        [self placeStatusAnimation];
        return;
    }
    ++_statusAnimationToken;
    _name.hiddenCustomEmoji = 0;
    _statusAnimationDocument = 0;
    [_statusAnimation removeFromSuperview];
    [_statusAnimation release];
    _statusAnimation = nil;
    if (!document || !NoshiLiteEnabled(NOSHI_LITE_EMOJI_CHAT)) return;
    _statusAnimationDocument = document;
    NSUInteger token = _statusAnimationToken;
    NoshiWeakReference *weak = _weak;
    [_session loadCustomEmojiDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] completion:^(NSArray *documents, NSString *errorName) {
        NoshiProfileController *profile = weak.target;
        if (!profile || token != profile->_statusAnimationToken) return;
        NoshiCustomEmojiDocument *found = documents.count ? [documents objectAtIndex:0] : nil;
        if (!found) {
            if (errorName) NSLog(@"noshigram: the status emoji %lld was not looked up: %@", document, errorName);
            return;
        }
        if (!found.file || (found.format != NOSHI_STICKER_ANIMATED && found.format != NOSHI_STICKER_VIDEO)) return;
        NSString *key = found.file.key;
        [profile->_media loadDataForFile:found.file completion:^(NSData *data) {
            NoshiProfileController *again = weak.target;
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
        NoshiProfileController *profile = weak.target;
        if (profile && token == profile->_statusAnimationToken) profile->_name.hiddenCustomEmoji = profile->_statusAnimationDocument;
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_statusAnimation setPlaying:!_hero];
}

/* the head takes the colors of the account: a collectible's own, or those of the color it picked from the server's list, which are asked for once */
- (void)applyBackdropOfPerson:(NoshiPerson *)person {
    if (person.hasBackdrop) {
        [self showBackdropCenter:person.backdropCenter edge:person.backdropEdge pattern:person.backdropPattern text:person.backdropText document:person.backdropPatternDocument];
        return;
    }
    if (!person.hasProfileColor) {
        [self dropBackdrop];
        return;
    }
    NoshiWeakReference *weak = _weak;
    int32_t colorId = (int32_t)person.profileColorId;
    long long emoji = person.profileColorEmoji;
    [NoshiProfileColors loadWithSession:_session completion:^{
        NoshiProfileController *profile = weak.target;
        uint32_t center = 0, edge = 0;
        if (!profile || ![NoshiProfileColors blendForColorId:colorId dark:NoshiThemeIsDark() center:&center edge:&edge]) return;
        [profile showBackdropCenter:center edge:edge pattern:0xFFFFFF text:0xFFFFFF document:emoji];
    }];
}

/* the colored ground goes when the account no longer wears a color, and the ink and the bar go back to those of the screen */
- (void)dropBackdrop {
    if (!_ground) return;
    [_ground removeFromSuperview];
    [_ground release];
    _ground = nil;
    [_groundInk release];
    _groundInk = nil;
    _bar.backgroundColor = [NoshiColorScreen() colorWithAlphaComponent:0.94];
    _name.textColor = NoshiColorTitle();
    _status.textColor = NoshiColorSecondary();
    for (NoshiProfileAction *action in [NSArray arrayWithObjects:_photoAction, _editAction, _settingsAction, nil]) [action setInk:nil];
    _music.patternColor = nil;
    _music.patternImage = nil;
    [self.view setNeedsLayout];
}

/* the blend behind the photo, the text over it, the action cards as veils with the same ink, and the emoji that tiles the ground */
- (void)showBackdropCenter:(uint32_t)center edge:(uint32_t)edge pattern:(uint32_t)pattern text:(uint32_t)text document:(long long)document {
    if (!_ground) {
        _ground = [[NoshiProfileBackdropView alloc] init];
        [_head insertSubview:_ground atIndex:0];
    }
    _ground.centerColor = NoshiColorOfRGB(center);
    _ground.edgeColor = NoshiColorOfRGB(edge);
    _ground.patternColor = NoshiColorOfRGB(pattern);
    _music.patternColor = NoshiColorOfRGB(pattern);
    _ground.photoRadius = _avatar.bounds.size.width / 2;
    /* the bar fills with the edge of the ground, darker, once the head has scrolled under it */
    const CGFloat keep = 0.5;
    _bar.backgroundColor = [UIColor colorWithRed:((edge >> 16) & 0xff) / 255.0 * keep green:((edge >> 8) & 0xff) / 255.0 * keep blue:(edge & 0xff) / 255.0 * keep alpha:0.94];
    UIColor *ink = NoshiColorOfRGB(text);
    [_groundInk release];
    _groundInk = [ink retain];
    _name.textColor = ink;
    _status.textColor = [ink colorWithAlphaComponent:0.78f];
    for (NoshiProfileAction *action in [NSArray arrayWithObjects:_photoAction, _editAction, _settingsAction, nil]) [action setInk:ink];
    if (document > 0) {
        NoshiWeakReference *weak = _weak;
        NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:document]], _session, _media, ^{
            [(NoshiProfileController *)weak.target showPatternOfDocument:document];
        });
        [self showPatternOfDocument:document];
    }
    [self.view setNeedsLayout];
    [_name setNeedsDisplay];
}

- (void)showPatternOfDocument:(long long)document {
    UIImage *picture = [NoshiCustomEmoji imageForDocument:document];
    if (!picture) return;
    _ground.patternImage = picture;
    _music.patternImage = picture;
}

- (NoshiProfileFeed *)feedForTab:(NSUInteger)tab {
    if (!_feeds[tab] && _person) {
        NoshiProfileFeedKind kind = tab == 0 ? NoshiFeedPinnedStories : (tab == 1 ? NoshiFeedArchivedStories : NoshiFeedGifts);
        NoshiDialog *own = [NoshiDialog savedMessagesWithPerson:_person];
        _feeds[tab] = [[NoshiProfileFeed alloc] initWithSession:_session kind:kind owner:own];
        if (tab == 2 && !_folderBar) {
            /* the folders of our own gifts, which this screen can also make, rename and delete */
            _folderBar = [[NoshiGiftFolderBar alloc] initWithSession:_session dialog:own mine:YES];
            _folderBar.delegate = self;
            [_head addSubview:_folderBar];
            [_folderBar reload];
        }
    }
    return _feeds[tab];
}

- (void)giftFolderBar:(NoshiGiftFolderBar *)bar didSelectFolder:(NoshiGiftFolder *)folder {
    (void)bar;
    [self reloadGiftsOfFolder:folder.folderId];
}

- (void)giftFolderBarDidChange:(NoshiGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged {
    if (selectionChanged) [self reloadGiftsOfFolder:bar.selectedFolder.folderId];
    [self.view setNeedsLayout];
}

- (void)reloadGiftsOfFolder:(int32_t)folderId {
    NoshiProfileFeed *feed = [self feedForTab:2];
    if (!feed) return;
    feed.folderId = folderId;
    NoshiWeakReference *me = _weak;
    [feed reload:^{ [(NoshiProfileController *)me.target feedChanged:2]; }];
}

- (void)selectTab:(NSUInteger)tab {
    _tab = tab;
    _tabs.selectedIndex = tab;
    _send.hidden = tab != 2;
    [_grid setTiles:[[self feedForTab:tab] tiles]];
    [self refreshCurrentFeed];
    [self showFeedState];
    [self.view setNeedsLayout];
}

- (void)refreshCurrentFeed {
    NoshiProfileFeed *feed = [self feedForTab:_tab];
    if (!feed || feed.loading) return;
    NoshiWeakReference *me = _weak;
    NSUInteger tab = _tab;
    [feed reload:^{ [(NoshiProfileController *)me.target feedChanged:tab]; }];
    [self showFeedState];
}

- (void)feedChanged:(NSUInteger)tab {
    if (tab != _tab) return;
    [_grid setTiles:[[self feedForTab:tab] tiles]];
    [self showFeedState];
}

/* under the tabs: a line for the empty list, the loading or the failure; nothing once there are tiles */
- (void)showFeedState {
    NoshiProfileFeed *feed = [self feedForTab:_tab];
    NSString *text = @"";
    if (!feed || !feed.loaded) text = feed.errorName ? [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), feed.errorName]
                                                     : NSLocalizedString(@"profile.loading", nil);
    else if (!feed.items.count) text = NSLocalizedString(_tab == 0 ? @"profile.stories.empty" : (_tab == 1 ? @"profile.archive.empty" : @"gifts.mine.empty"), nil);
    if ([_empty.text isEqualToString:text]) return;
    _empty.text = text;
    [self layoutHead];
}

- (void)giftGridReachedEnd:(NoshiGiftGridView *)grid {
    (void)grid;
    NoshiWeakReference *me = _weak;
    NSUInteger tab = _tab;
    [[self feedForTab:tab] loadMore:^{ [(NoshiProfileController *)me.target feedChanged:tab]; }];
}

- (void)giftGrid:(NoshiGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    NoshiProfileFeed *feed = [self feedForTab:_tab];
    if (index >= feed.items.count || !_person) return;
    if (_tab == 2) {
        NoshiGiftDetailController *detail = [[[NoshiGiftDetailController alloc] initWithSession:_session gift:[feed.items objectAtIndex:index] mine:YES
                                                                                            avatars:_avatars media:_media] autorelease];
        detail.ownerName = _person.name;
        detail.stickers = _stickerLibrary;
        detail.folderDialog = [NoshiDialog savedMessagesWithPerson:_person];
        detail.pinnedGifts = [feed.items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pinned == YES"]];
        NoshiWeakReference *me = _weak;
        detail.changedHandler = ^{ NoshiProfileController *profile = me.target; [profile refreshCurrentFeed]; [profile->_folderBar reload]; };
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    NoshiDialog *own = [NoshiDialog savedMessagesWithPerson:_person];
    /* a second tap while a viewer is up or rising would stack another viewer on the first, and both would play the same story's sound */
    if (self.presentedViewController) return;
    NoshiStoryViewerController *viewer = [[[NoshiStoryViewerController alloc] initWithSession:_session owner:own stories:feed.items index:index
                                                                                          avatars:_avatars media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark layout

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    [self.view setNeedsLayout];
}

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

/* the head scrolls with the tiles, so it has a fixed frame that this works out from the width */
- (void)layoutHead {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;
    CGFloat contentWidth = MIN(width - 32, 460);
    CGFloat x = (width - contentWidth) / 2;
    CGFloat y = NOSHI_IDENTITY_TOP;
    CGFloat identityExtra = [_identity extraHeightForWidth:width];
    _identity.frame = CGRectMake(0, y, width, NOSHI_IDENTITY_HEIGHT + identityExtra);
    [_identity layoutIfNeeded];
    CGFloat wideHeight = _heroOpen ? _heroHeight : 0;
    /* the photo reaches up under the bar and the status bar: its frame begins above the head by the inset of the list */
    if (_hero) _hero.frame = _heroOpen ? CGRectMake(0, -_grid.topInset, width, _grid.topInset + wideHeight) : _heroCircle;
    [self placeStatusAnimation];
    CGFloat statusWidth = MIN(width - 70, ceil([_status sizeThatFits:CGSizeMake(width - 70, 22)].width));
    _ratingBadge.frame = CGRectMake(floor((width - statusWidth) / 2) - 26, _status.frame.origin.y + 1, 22, 20);
    y += NOSHI_IDENTITY_HEIGHT + identityExtra + GAP + 4;
    /* open wide, the buttons stand over the lower edge of the photo and the rest of the head starts under it */
    if (_heroOpen) y = wideHeight - ACTION_HEIGHT - 12;
    CGFloat slot = floor((contentWidth - 2 * ACTION_GAP) / 3);
    _photoAction.frame = CGRectMake(x, y, slot, ACTION_HEIGHT);
    _editAction.frame = CGRectMake(x + slot + ACTION_GAP, y, slot, ACTION_HEIGHT);
    _settingsAction.frame = CGRectMake(x + 2 * (slot + ACTION_GAP), y, contentWidth - 2 * (slot + ACTION_GAP), ACTION_HEIGHT);
    y += ACTION_HEIGHT + GAP;
    if (_ground) {
        /* the ground runs up under the bar and down behind the buttons; the wide photo ends the head itself, so the ground shows no strip under it */
        CGFloat above = 600;
        CGFloat groundBottom = _heroOpen ? wideHeight : y - GAP + 6;
        _ground.frame = CGRectMake(0, -above, width, above + groundBottom);
        _ground.focus = CGPointMake(width / 2, above + CGRectGetMidY([_identity convertRect:_avatar.frame toView:_head]));
    }
    if (_heroOpen) y = wideHeight + GAP;
    if (_music.hasContent) {
        CGFloat pillWidth = [_music widthWithin:contentWidth];
        _music.frame = CGRectMake(x + floor((contentWidth - pillWidth) / 2), y - GAP + 8, pillWidth, [NoshiMusicPill height]);
        y += [NoshiMusicPill height] + 8;
    }
    if (!_channelCard.hidden) {
        _channelCard.frame = CGRectMake(x, y, contentWidth, [NoshiChannelCard height]);
        y += [NoshiChannelCard height] + GAP;
    }
    if (!_info.hidden) {
        CGFloat height = [_info heightForWidth:contentWidth];
        _info.frame = CGRectMake(x, y, contentWidth, height);
        y += height + GAP;
    }
    y += 4;
    _tabs.frame = CGRectMake(x, y, contentWidth, 40);
    y += 40 + 12;
    CGFloat folders = _tab == 2 ? [_folderBar height] : 0;
    _folderBar.hidden = folders == 0;
    _folderBar.frame = CGRectMake(x, y - 12, contentWidth, folders);
    y += folders;
    CGSize empty = _empty.text.length ? [_empty sizeThatFits:CGSizeMake(contentWidth - 16, 200)] : CGSizeZero;
    _empty.frame = CGRectMake(x + 8, y + 16, contentWidth - 16, empty.height);
    y += empty.height ? empty.height + 40 : 0;
    if (fabs(y - _headHeight) > 0.5 || fabs(width - _headWidth) > 0.5) {
        _headHeight = y;
        _headWidth = width;
        _head.frame = CGRectMake(0, 0, width, y);
        if (_heroMoving) [_grid setHeaderViewAnimated:_head];
        else _grid.headerView = _head;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    CGFloat barHeight = insets.top + BAR_HEIGHT;
    /* the wave and the bar plate run full width; the bar's words, the tiles and the button stand in one column */
    CGRect column = NoshiContentColumn(size, insets, NOSHI_COLUMN_PAGE);
    CGFloat left = column.origin.x, width = column.size.width, edge = CGRectGetMaxX(column);
    _backdrop.frame = self.view.bounds;
    _bar.frame = CGRectMake(0, 0, size.width, barHeight);
    _titleLabel.frame = CGRectMake(left + 60, insets.top, width - 120, BAR_HEIGHT);
    _barName.frame = CGRectMake(left + 60, insets.top + 3, width - 120, 22);
    _barStatus.frame = CGRectMake(left + 60, insets.top + 24, width - 120, 16);
    /* the list runs under the status bar and the bar, so a photo opened wide in its head can reach the top of the screen; its first row starts under the bar all the same */
    [_grid setFrame:CGRectMake(left, 0, width, size.height) topInset:insets.top + BAR_HEIGHT];
    _grid.bottomInset = _bottomInset + (_tab == 2 ? SEND_HEIGHT + 24 : 0);
    CGFloat sendWidth = MIN(width - 64, 280);
    _send.frame = CGRectMake(CGRectGetMidX(column) - sendWidth / 2, size.height - _bottomInset - SEND_HEIGHT - 16, sendWidth, SEND_HEIGHT);
    _toast.frame = CGRectMake(CGRectGetMidX(column) - 80, barHeight + 12, 160, 28);
    _qrButton.frame = CGRectMake(left + 6, insets.top, 48, BAR_HEIGHT);
    _moreButton.frame = CGRectMake(edge - 54, insets.top, 48, BAR_HEIGHT);
    _spinner.center = _moreButton.center;
    [self layoutHead];
}

/* the plain "profile" title gives way to the name once the head has scrolled up */
- (void)giftGrid:(NoshiGiftGridView *)grid didScrollToOffset:(CGFloat)offset {
    (void)grid;
    /* a pull of the list down past its top takes the wide photo away */
    [self heroFollowsPull:-(offset + _grid.topInset)];
    CGFloat limit = 140;
    offset += _grid.topInset;
    CGFloat mix = MAX(0, MIN(1, (offset - limit + 40) / 40));
    BOOL filled = offset > 0.5;
    if (filled != _barFilled) {
        _barFilled = filled;
        [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.42 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ _bar.alpha = filled ? 1 : 0; } completion:nil];
    }
    _titleLabel.alpha = _heroOpen ? 0 : 1 - mix;
    _barName.alpha = mix;
    _barStatus.alpha = mix;
}

#pragma mark channel and code

/* the personal channel under the buttons: its name, its followers and the newest line it shows */
- (void)refreshChannelCard {
    NoshiPersonalChannel *channel = _full.channel;
    _channelCard.hidden = channel == nil;
    if (channel) [_channelCard configureWithChannel:channel avatars:_avatars];
}

- (void)openRating { NoshiShowRating(self.view.window, _full); }

- (void)openMusic {
    if (!_person || !_media) return;
    NoshiMusicListController *list = [[[NoshiMusicListController alloc] initWithSession:_session dialog:[NoshiDialog savedMessagesWithPerson:_person]
                                                                                    first:_full.music avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openChannel {
    NoshiPersonalChannel *channel = _full.channel;
    if (!channel || !_media) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:channel.dialog avatars:_avatars media:_media
                                                                         stickers:_stickerLibrary] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

/* the dots hold what is only needed now and then: the link of the username, the peek at being online, a photo to remove, and the sign out */
- (void)showMenu {
    if (_working) return;
    BOOL hasLink = _person.username.length > 0;
    BOOL hasPhoto = _person.photo != nil;
    NSMutableArray *titles = [NSMutableArray array];
    NoshiSymbol symbols[4];
    NSUInteger count = 0;
    if (hasLink) {
        [titles addObject:NSLocalizedString(@"profile.qr.copy", nil)];
        symbols[count++] = NoshiSymbolLink;
    }
    if (hasPhoto) {
        [titles addObject:NSLocalizedString(@"profile.photo.delete", nil)];
        symbols[count++] = NoshiSymbolTrash;
    }
    [titles addObject:NSLocalizedString(@"profile.signout", nil)];
    symbols[count++] = NoshiSymbolLogout;
    NoshiWeakReference *me = _weak;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols
                                                              handler:^(NSUInteger index) {
        NoshiProfileController *profile = me.target;
        NSUInteger at = 0;
        if (hasLink && index == at++) [profile copyLink];
        else if (hasPhoto && index == at++) [profile confirmDeletePhoto];
        else [profile confirmSignOut];
    }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_moreButton.frame) - 6, CGRectGetMaxY(_moreButton.frame) - 8)];
}

- (void)confirmDeletePhoto {
    NoshiWeakReference *me = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"profile.photo.delete.confirm", nil), NSLocalizedString(@"profile.photo.delete", nil), ^{
        [(NoshiProfileController *)me.target deletePhoto];
    });
}

/* the newest profile photo is the one on show, so the list is asked for at the moment of the tap and its first item goes */
- (void)deletePhoto {
    if (_uploading || !_person) return;
    _uploading = YES;
    [_identity setUploading:YES];
    [self retain];
    void (^failed)(NSString *) = ^(NSString *errorName) {
        NSLog(@"noshigram: profile photo not removed: %@", errorName);
        [self toast:NSLocalizedString(@"profile.photo.delete.failed", nil)];
    };
    [_session loadAvatarsOfDialog:[NoshiDialog savedMessagesWithPerson:_person] completion:^(NSArray *photos, NSString *listError) {
        if (listError || !photos.count) {
            [self autorelease];
            _uploading = NO;
            [_identity setUploading:NO];
            if (listError) failed(listError);
            else [self loadProfile];
            return;
        }
        [_session deleteProfilePhoto:[photos objectAtIndex:0] completion:^(NSString *errorName) {
            [self autorelease];
            _uploading = NO;
            [_identity setUploading:NO];
            if (errorName) failed(errorName);
            else [self loadProfile];
        }];
    }];
}

- (void)copyLink {
    if (!_person.username.length) return;
    [UIPasteboard generalPasteboard].string = [@"https://t.me/" stringByAppendingString:_person.username];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

- (void)openQr {
    if (!_person) return;
    NoshiProfileQrController *code = [[[NoshiProfileQrController alloc] initWithSession:_session person:_person avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:code animated:YES];
}

#pragma mark actions

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}


- (void)editProfile {
    if (!_person) return;
    NoshiProfileEditController *edit = [[[NoshiProfileEditController alloc] initWithSession:_session person:_person fullUser:_full avatars:_avatars
                                                                                          media:_media] autorelease];
    NoshiWeakReference *me = _weak;
    edit.changedHandler = ^{ [(NoshiProfileController *)me.target loadProfile]; };
    edit.logoutHandler = ^{ [(NoshiProfileController *)me.target confirmSignOut]; };
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)openSettings {
    [_delegate profileControllerRequestsSettings:self];
}

- (void)choosePhoto {
    if (_uploading) return;
    NoshiWeakReference *me = _weak;
    [NoshiProfilePhotoPicker pickWithSheetIn:NoshiOverlayHost() picked:^(NSString *path, BOOL video) {
        NoshiProfileController *profile = me.target;
        if (!profile) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [profile uploadPhotoAtPath:path video:video];
    } failed:^{
        NoshiProfileController *profile = me.target;
        if (profile) [profile toast:NSLocalizedString(@"attach.failed", nil)];
    }];
}

- (void)uploadPhotoAtPath:(NSString *)path video:(BOOL)video {
    _uploading = YES;
    [_identity setUploading:YES];
    [self toast:NSLocalizedString(@"profile.photo.uploading", nil)];
    [self retain];
    void (^finished)(NSString *) = ^(NSString *errorName) {
        [self autorelease];
        _uploading = NO;
        [_identity setUploading:NO];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (errorName) {
            NSLog(@"noshigram: profile photo not set: %@", errorName);
            [self toast:NSLocalizedString(@"profile.photo.failed", nil)];
            return;
        }
        [self loadProfile];
        [_hero reloadPhotos];
    };
    if (video) [_session uploadProfileVideoAtPath:path completion:finished];
    else [_session uploadProfilePhotoAtPath:path completion:finished];
}

- (void)sendGifts {
    if (!_person || !_media) return;
    NoshiContactPickerController *picker = [[[NoshiContactPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"gifts.send", nil);
    picker.selfPerson = _person;
    NoshiWeakReference *me = _weak;
    NoshiWeakReference *pickerRef = [NoshiWeakReference referenceTo:picker];
    picker.pickHandler = ^(NoshiDialog *dialog) {
        NoshiProfileController *profile = me.target;
        UIViewController *host = pickerRef.target;
        if (!profile || !host) return;
        NoshiGiftCatalogController *catalog = [[[NoshiGiftCatalogController alloc] initWithSession:profile->_session dialog:dialog avatars:profile->_avatars
                                                                                                  media:profile->_media] autorelease];
        catalog.sentHandler = ^{ [(NoshiProfileController *)me.target refreshCurrentFeed]; };
        /* the list gives way to the catalog, so the way back from a sent gift leads to the profile */
        UINavigationController *navigation = host.navigationController;
        [navigation popViewControllerAnimated:NO];
        [navigation pushViewController:catalog animated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark sign out

- (void)confirmSignOut {
    if (_working) return;
    NoshiWeakReference *me = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"profile.signout.confirm", nil), NSLocalizedString(@"profile.signout", nil),
                         ^{ [(NoshiProfileController *)me.target signOutNow]; });
}

- (void)signOutNow {
    _working = YES;
    _moreButton.hidden = YES;
    [_spinner startAnimating];
    [_delegate profileController:self requestsSignOut:^(NSString *errorName) {
        _working = NO;
        _moreButton.hidden = NO;
        [_spinner stopAnimating];
        if (!errorName) return;
        Class alertClass = NoshiAlertClass();
        id failure = [[alertClass alloc] initWithTitle:nil
                                               message:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                              delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [failure show];
        [failure release];
    }];
}

@end
