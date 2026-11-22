#import <QuartzCore/QuartzCore.h>
#import "noshi_classic_profile_controller.h"
#import "noshi_text_filter.h"

#import "noshi_avatar_view.h"
#import "noshi_classic_chrome.h"
#import "noshi_chat_settings.h"
#import "noshi_avatar_viewer.h"
#import "noshi_avatar_viewer.h"
#import "noshi_accounts.h"
#import "noshi_profile_hero_view.h"
#import "noshi_dialog.h"
#import "noshi_emoji_label.h"
#import "noshi_info_card_view.h"
#import "noshi_info_rows.h"
#import "noshi_music_pill.h"
#import "noshi_link_router.h"
#import "noshi_name_badge.h"
#import "noshi_chat_controller.h"
#import "noshi_gifts_controller.h"
#import "noshi_profile_qr_controller.h"
#import "noshi_profile_edit_controller.h"
#import "noshi_rating_view.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_music_list_controller.h"
#import "noshi_music_player.h"
#import "noshi_settings_controller.h"
#import "noshi_symbol.h"
#import "noshi_session_profile.h"
#import "noshi_star_gift.h"
#import "noshi_story_feed_controller.h"
#import "noshi_person.h"
#import "noshi_platform.h"
#import "noshi_alert.h"
#import "noshi_theme.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

/* the profile of the account as telegram for ios 4 drew it: a white head of 97 points with the photo of 66 at the left and the name, the number and the username
   beside it, then white groups of rows on the grey ground */
#define AVATAR 66.0
#define HEAD_TOP 18.0
#define HEAD_HEIGHT 97.0
#define HEAD_TEXT_X 92.0

/* a row with a small caption over its value, as the user info of telegram for ios 4 had them; the value is the user's own text (a bio, a channel name), so it is
   drawn by the emoji label and not by the cell's textLabel, which shows the system's emoji font */
@interface NoshiClassicInfoCell : UITableViewCell {
    NoshiEmojiLabel *_value;
    NoshiEmojiLabel *_caption;
    NoshiWeakReference *_weak;
    BOOL _row;
}
- (void)setValue:(NSString *)value caption:(NSString *)caption;
/* the cell stands as a plain row of the list: the title at the margin of the others, with custom emoji after the words */
- (void)setRowTitle:(NSString *)title entities:(NSArray *)entities;
- (NoshiEmojiLabel *)valueLabel;
- (NoshiWeakReference *)weakReference;
/* the height a row needs for the table width; it assumes the widest grouped margin, so a row never clips a line */
+ (CGFloat)heightForValue:(NSString *)value caption:(NSString *)caption tableWidth:(CGFloat)width hasImage:(BOOL)hasImage;
@end

#define INFO_PAD 15.0
#define INFO_MARGIN 20.0
#define INFO_VALUE_LINES 6

@implementation NoshiClassicInfoCell

static UIFont *NoshiClassicInfoValueFont(void) { return [UIFont systemFontOfSize:17]; }
static UIFont *NoshiClassicInfoCaptionFont(void) { return [UIFont systemFontOfSize:14]; }

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    BOOL dark = NoshiThemeIsDark();
    _value = [[NoshiEmojiLabel alloc] init];
    _value.font = NoshiClassicInfoValueFont();
    _value.textColor = dark ? NoshiColorTitle() : [UIColor blackColor];
    _value.numberOfLines = INFO_VALUE_LINES;
    [self.contentView addSubview:_value];
    _caption = [[NoshiEmojiLabel alloc] init];
    _caption.font = NoshiClassicInfoCaptionFont();
    _caption.textColor = dark ? NoshiColorTitle() : [UIColor blackColor];
    [self.contentView addSubview:_caption];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_value release];
    [_caption release];
    [super dealloc];
}

- (void)setValue:(NSString *)value caption:(NSString *)caption {
    _value.text = value;
    BOOL bio = [caption isEqualToString:NSLocalizedString(@"profile.about", nil)];
    _value.entities = bio ? NoshiInfoMentions(value) : nil;
    _value.linkColor = bio ? NoshiColorAccent() : nil;
    _value.userInteractionEnabled = bio;
    if (bio && !_value.gestureRecognizers.count) {
        UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBio:)] autorelease];
        [_value addGestureRecognizer:tap];
    }
    _caption.text = caption;
    /* the number and the name to reach the account by are in the accent */
    BOOL reachable = [caption isEqualToString:NSLocalizedString(@"profile.phone", nil)] || [caption isEqualToString:NSLocalizedString(@"profile.username", nil)];
    _value.textColor = reachable ? NoshiColorAccent() : (NoshiThemeIsDark() ? NoshiColorTitle() : [UIColor blackColor]);
    [self setNeedsLayout];
}

- (void)tapBio:(UITapGestureRecognizer *)tap {
    NSString *link = [_value linkAtPoint:[tap locationInView:_value]];
    if (link.length) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenLinkNotification object:self
                                                                       userInfo:[NSDictionary dictionaryWithObject:link forKey:@"url"]];
}

- (NoshiEmojiLabel *)valueLabel { return _value; }
- (NoshiWeakReference *)weakReference { return _weak; }

- (void)setRowTitle:(NSString *)title entities:(NSArray *)entities {
    _row = YES;
    _value.font = [UIFont systemFontOfSize:17];
    _value.numberOfLines = 1;
    [self setValue:title caption:nil];
    _value.entities = entities;
}

+ (CGFloat)heightForValue:(NSString *)value caption:(NSString *)caption tableWidth:(CGFloat)width hasImage:(BOOL)hasImage {
    CGFloat room = width - 2 * INFO_MARGIN - 2 * INFO_PAD - (hasImage ? 34 : 0);
    NoshiEmojiLabel *probe = [[[NoshiEmojiLabel alloc] init] autorelease];
    probe.font = NoshiClassicInfoValueFont();
    probe.numberOfLines = INFO_VALUE_LINES;
    probe.text = value;
    CGFloat text = ceil([probe sizeThatFits:CGSizeMake(MAX(room, 1), CGFLOAT_MAX)].height);
    return MAX(caption.length ? 58 : 44, text + (caption.length ? 19 : 0) + 22);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat left = INFO_PAD;
    if (self.imageView.image) left = CGRectGetMaxX(self.imageView.frame) + 10;
    CGFloat width = MAX(1, bounds.size.width - left - INFO_PAD);
    CGFloat captionHeight = _caption.text.length ? 19 : 0;
    CGSize fit = [_value sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat valueHeight = ceil(fit.height);
    CGFloat top = floor((bounds.size.height - valueHeight - captionHeight) / 2);
    _caption.frame = CGRectMake(left, top, width, captionHeight);
    _value.frame = CGRectMake(left, top + captionHeight, width, valueHeight);
}

@end

@interface NoshiClassicProfileController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickerLibrary;
    NoshiPerson *_person;
    NSString *_about;
    NoshiFullUser *_full;
    NSString *_starsText;
    NSArray *_infoRows;
    BOOL _uploading;
    NoshiAvatarView *_avatar;
    NoshiProfileHeroView *_hero;
    CGRect _heroCircle;
    BOOL _heroOpen;
    BOOL _heroMoving;
    BOOL _viewerWanted;
    UIView *_headPanel;
    NoshiEmojiLabel *_name;
    UILabel *_detail;
    UILabel *_handle;
    NoshiRatingBadge *_ratingBadge;
    UIView *_actionsGroup;
    NoshiInfoRow *_photoRow;
    NoshiInfoRow *_editRow;
    UIView *_musicGroup;
    NoshiMusicPill *_music;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    void (^_signOutHandler)(void (^)(NSString *));
}
@end

@implementation NoshiClassicProfileController

@synthesize signOutHandler = _signOutHandler;
@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _session = [session retain];
    _avatars = [avatars retain];
    self.title = NSLocalizedString(@"tab.profile", nil);
    return self;
}

/* the photo opened wide in the header of the list: the circle grows to the width of the screen and the rows move down, so it scrolls with the list */
- (void)openAvatars {
    if (_hero || !_person || _heroMoving) return;
    /* with no photo there is nothing to open wide, and the viewer would be a black screen */
    if (!_person.photo && !_full.publicPhoto) return;
    UITableView *table = self.tableView;
    UIView *header = table.tableHeaderView;
    NoshiProfileHeroView *hero = [[[NoshiProfileHeroView alloc] initWithSession:_session dialog:[NoshiDialog savedMessagesWithPerson:_person] avatars:_avatars media:_media] autorelease];
    hero.name.text = _name.text;
    hero.name.entities = _name.entities;
    hero.status.text = _handle.text.length ? [NSString stringWithFormat:@"%@  %@", _detail.text, _handle.text] : _detail.text;
    /* the classic profile has no cards on the lower edge of the photo, so the words stand on it instead of high above it */
    hero.bottomRoom = 18;
    hero.publicPhoto = _full.publicPhoto;
    [hero setRatingLevel:_ratingBadge.hidden ? 0 : _ratingBadge.level target:self action:@selector(openRating)];
    _heroCircle = _avatar.frame;
    hero.frame = _heroCircle;
    hero.layer.cornerRadius = _heroCircle.size.width / 2;
    [hero beginMove];
    [header insertSubview:hero aboveSubview:_avatar];
    _hero = [hero retain];
    _heroOpen = YES;
    _heroMoving = YES;
    BOOL motion = !NoshiReduceMotionEnabled();
    [hero animateCornerTo:0 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _name.alpha = 0;
        _detail.alpha = 0;
        _handle.alpha = 0;
        /* the hero draws its own badge on its status line; the one of the header would stay over the wide photo, on top of the name */
        _ratingBadge.alpha = 0;
        [self layoutHeroHeader];
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
    _avatar.hidden = NO;
    [_hero beginClose];
    BOOL motion = !NoshiReduceMotionEnabled();
    [_hero animateCornerTo:_heroCircle.size.width / 2 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _name.alpha = 1;
        _detail.alpha = 1;
        _handle.alpha = 1;
        _ratingBadge.alpha = 1;
        [self layoutHeroHeader];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        [_hero removeFromSuperview];
        [_hero release];
        _hero = nil;
    }];
}

/* the header is as tall as the wide photo while it is open and as it was before; the list under it slides with the change */
- (void)layoutHeroHeader {
    UITableView *table = self.tableView;
    UIView *header = table.tableHeaderView;
    CGFloat width = table.bounds.size.width;
    CGFloat wide = [NoshiProfileHeroView heightForWidth:width screenHeight:self.view.bounds.size.height];
    if (_hero) _hero.frame = _heroOpen ? CGRectMake(0, 0, width, wide) : _heroCircle;
    CGRect frame = header.frame;
    frame.size.height = [self layoutBlocksBelow:_heroOpen ? wide : HEAD_TOP + HEAD_HEIGHT width:width];
    header.frame = frame;
    [table beginUpdates];
    table.tableHeaderView = header;
    [table endUpdates];
}

/* the photo and the edit rows and the song stand under the head, or under the wide photo while it is open; returns the height the header needs */
- (CGFloat)layoutBlocksBelow:(CGFloat)photoBottom width:(CGFloat)width {
    CGFloat y = photoBottom + NOSHI_INFO_SECTION_GAP;
    y += NoshiLayoutInfoGroup(_actionsGroup, [NSArray arrayWithObjects:_photoRow, _editRow, nil], y, width);
    _musicGroup.hidden = !_music.hasContent;
    if (_music.hasContent) {
        y += NOSHI_INFO_SECTION_GAP;
        _musicGroup.frame = CGRectMake(0, y, width, [NoshiMusicPill height]);
        _music.frame = _musicGroup.bounds;
        NoshiFitInfoGroupLines(_musicGroup, YES);
        y += [NoshiMusicPill height];
    }
    /* the grouped list puts no gap above its first group here, so the head keeps the grey of one under its last row */
    return y + NOSHI_INFO_SECTION_GAP;
}

/* the header grows with the song that arrives after the full profile */
- (void)fitHeader {
    UITableView *table = self.tableView;
    UIView *header = table.tableHeaderView;
    if (!header || _heroMoving) return;
    CGFloat width = table.bounds.size.width;
    CGFloat photoBottom = _heroOpen ? [NoshiProfileHeroView heightForWidth:width screenHeight:self.view.bounds.size.height] : HEAD_TOP + HEAD_HEIGHT;
    CGFloat height = [self layoutBlocksBelow:photoBottom width:width];
    if (fabs(header.frame.size.height - height) < 0.5) return;
    CGRect frame = header.frame;
    frame.size.height = height;
    header.frame = frame;
    table.tableHeaderView = header;
}

- (void)openMusic {
    NoshiDialog *own = _person && _media ? [NoshiDialog savedMessagesWithPerson:_person] : nil;
    if (!own) return;
    NoshiMusicListController *list = [[[NoshiMusicListController alloc] initWithSession:_session dialog:own first:_full.music avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)editProfile {
    if (!_person) return;
    NoshiProfileEditController *edit = [[[NoshiProfileEditController alloc] initWithSession:_session person:_person fullUser:_full avatars:_avatars media:_media] autorelease];
    NoshiWeakReference *weak = _weak;
    edit.changedHandler = ^{ [(NoshiClassicProfileController *)weak.target loadProfile]; };
    edit.logoutHandler = ^{ [(NoshiClassicProfileController *)weak.target confirmSignOut]; };
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    /* a tab nobody opened has no view, and asking for it here would load one while the controller is being freed */
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiChatSettingsDidChangeNotification object:nil];
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_signOutHandler release];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickerLibrary release];
    [_person release];
    [_about release];
    [_full release];
    [_starsText release];
    [_infoRows release];
    [_hero release];
    [_avatar release];
    [_headPanel release];
    [_name release];
    [_detail release];
    [_handle release];
    [_ratingBadge release];
    [_actionsGroup release];
    [_photoRow release];
    [_editRow release];
    [_musicGroup release];
    [_music release];
    [_spinner release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged) name:NoshiChatSettingsDidChangeNotification object:nil];
    UITableView *table = self.tableView;
    NoshiClassicStyleTable(table);
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, HEAD_TOP + HEAD_HEIGHT)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _headPanel = NoshiNewInfoGroup();
    [header addSubview:_headPanel];
    _avatar = [[NoshiAvatarView alloc] initWithFrame:CGRectMake(15, HEAD_TOP + floor((HEAD_HEIGHT - AVATAR) / 2), AVATAR, AVATAR)];
    _avatar.accent = YES;
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatars)] autorelease]];
    [header addSubview:_avatar];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.font = NoshiFontMedium(20);
    _name.textColor = NoshiColorTitle();
    /* as every other name of the app is drawn: letters of a styled nick that the system font lacks are dropped, not shown as boxes */
    _name.dropsUndrawable = YES;
    [header addSubview:_name];
    for (int i = 0; i < 2; ++i) {
        UILabel *line = [[UILabel alloc] init];
        line.backgroundColor = [UIColor clearColor];
        line.font = [UIFont systemFontOfSize:15];
        line.textColor = NoshiColorSecondary();
        [header addSubview:line];
        if (i == 0) _detail = line;
        else _handle = line;
    }
    _ratingBadge = [[NoshiRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    [_ratingBadge addTarget:self action:@selector(openRating) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_ratingBadge];
    _actionsGroup = NoshiNewInfoGroup();
    _photoRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.setphoto", nil) accent:YES chevron:NO target:self action:@selector(choosePhoto)];
    _editRow = [[NoshiInfoRow alloc] initWithTitle:NSLocalizedString(@"profile.row.edit", nil) accent:YES chevron:NO target:self action:@selector(editProfile)];
    [_actionsGroup addSubview:_photoRow];
    [_actionsGroup addSubview:_editRow];
    [header addSubview:_actionsGroup];
    _musicGroup = NoshiNewInfoGroup();
    _music = [[NoshiMusicPill alloc] init];
    _music.media = _media;
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    NoshiWeakReference *musicWeak = _weak;
    _music.contentHandler = ^{ [[(NoshiClassicProfileController *)musicWeak.target view] setNeedsLayout]; };
    [_musicGroup addSubview:_music];
    [header addSubview:_musicGroup];
    header.frame = CGRectMake(0, 0, table.bounds.size.width, [self layoutBlocksBelow:HEAD_TOP + HEAD_HEIGHT width:table.bounds.size.width]);
    table.tableHeaderView = header;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [self loadProfile];
}

/* a long pull goes through the whole opening of the wide photo in one drag: the part that came while it opened is kept, or the photos would ask for a second pull */
- (BOOL)holdsPullWhileOpening:(CGFloat)pull {
    if (!_heroMoving) return NO;
    if (_heroOpen && pull > 130) _viewerWanted = YES;
    return YES;
}

/* the screen's own swipes: a pull down opens the photo wide, a longer one opens the photos, and scrolling up closes the wide photo */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat pull = -(scrollView.contentOffset.y + scrollView.contentInset.top);
    if ([self holdsPullWhileOpening:pull]) return;
    if (!_hero) {
        if (pull > 60) [self openAvatars];
    } else if (_heroOpen) {
        /* the pull down goes on from the wide photo to the photos on the whole screen, and scrolling up takes it back to the circle */
        if (pull > 130) [self openAvatarViewer];
        else if (-pull > 90) [self closeHero];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    UIView *header = self.tableView.tableHeaderView;
    if (header && width > 0 && header.frame.size.width != width) {
        CGRect frame = header.frame;
        frame.size.width = width;
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
    _headPanel.frame = CGRectMake(0, HEAD_TOP, width, HEAD_HEIGHT);
    NoshiFitInfoGroupLines(_headPanel, YES);
    _avatar.frame = CGRectMake(15, HEAD_TOP + floor((HEAD_HEIGHT - AVATAR) / 2), AVATAR, AVATAR);
    if (_hero && !_heroMoving) _hero.frame = _heroOpen ? CGRectMake(0, 0, width, [NoshiProfileHeroView heightForWidth:width screenHeight:self.view.bounds.size.height]) : _avatar.frame;
    /* the name over the number over the username, as one block beside the photo; the rating badge leads the number */
    CGFloat textWidth = MAX(0, width - HEAD_TEXT_X - 15);
    BOOL handle = _handle.text.length > 0;
    CGFloat block = 25 + 20 + (handle ? 20 : 0);
    CGFloat y = HEAD_TOP + floor((HEAD_HEIGHT - block) / 2);
    _name.frame = CGRectMake(HEAD_TEXT_X, y, textWidth, 25);
    y += 25;
    CGFloat badge = _ratingBadge.hidden ? 0 : 26;
    _ratingBadge.frame = CGRectMake(HEAD_TEXT_X, y, 22, 20);
    _detail.frame = CGRectMake(HEAD_TEXT_X + badge, y, MAX(0, textWidth - badge), 20);
    _handle.hidden = !handle;
    _handle.frame = CGRectMake(HEAD_TEXT_X, y + 20, textWidth, 20);
    [self fitHeader];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

/* the name, the line under it, the photo and the rows, from the person that is held */
- (void)chatSettingsChanged {
    if (_person) [self showPerson];
}

- (void)showPerson {
    NSArray *hammer = nil;
    /* the mark after the name is the one the lists and the chat show: the status the person chose, or the Premium star */
    long long badge = NoshiPersonBadgeDocument(_person);
    _name.text = NoshiNameWithBadge(_person.name, badge, &hammer);
    _name.entities = hammer;
    NoshiWeakReference *weak = _weak;
    NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:badge]], _session, _media, ^{
        NoshiClassicProfileController *profile = weak.target;
        if (profile) [profile->_name setNeedsDisplay];
    });
    BOOL service = _person.userId == NOSHI_TELEGRAM_SERVICE_USER_ID;
    _detail.text = service ? NSLocalizedString(@"chat.status.telegram", nil) : (_person.phone.length ? NoshiOwnPhoneText(_person.phone) : @"");
    _handle.text = !service && _person.username.length ? [@"@" stringByAppendingString:_person.username] : @"";
    [self.view setNeedsLayout];
    _avatar.initials = _person.initials;
    _avatar.deleted = _person.deleted;
    _avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [_avatar setPhoto:_person.photo cache:_avatars];
    [self rebuildInfo];
}

- (void)loadProfile {
    /* the profile of the last time draws at once, and the answer corrects it */
    if (!_person && [_session ownPerson]) {
        _person = [[_session ownPerson] retain];
        [_avatars pinPhoto:_person.photo];
        [self showPerson];
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
        [self showPerson];
        [self loadFull];
    }];
    [self retain];
    [_session loadStarsBalance:^(long long stars, NSString *errorName) {
        [self autorelease];
        if (errorName) return;
        [_starsText release];
        _starsText = [NoshiStarsText(stars) copy];
        [self rebuildInfo];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* the public photo is set and removed on the privacy page, so the full profile is asked again to show it without a reopen */
    [self loadFull];
}

/* the bio, the birthday and the personal channel come with the full profile */
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
        _hero.publicPhoto = user.publicPhoto;
        _ratingBadge.hidden = !user.hasRating;
        _ratingBadge.level = user.rating.level;
        _ratingBadge.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)user.rating.level];
        _music.media = _media;
        _music.savedTrack = user.music;
        [self.view setNeedsLayout];
        [_about release];
        _about = [user.about copy];
        [self rebuildInfo];
    }];
}

- (void)openRating { NoshiShowRating(self.view.window, _full); }

/* the phone, the bio and the username, each only when there is one; a tap copies it */
- (void)rebuildInfo {
    NSMutableArray *rows = [NSMutableArray array];
    if (_person.phone.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.phone", nil), NoshiOwnPhoneText(_person.phone), nil]];
    if (_about.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.about", nil), _about, nil]];
    if (_person.username.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.username", nil), [@"@" stringByAppendingString:_person.username], nil]];
    if (_full.hasBirthday) {
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        parts.day = _full.birthdayDay;
        parts.month = _full.birthdayMonth;
        parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
        if (date) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.birthday", nil), [formatter stringFromDate:date], nil]];
    }
    [rows addObjectsFromArray:NoshiIdentityRows(_person.userId, _person.photo)];
    if (_starsText.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.stars", nil), _starsText, nil]];
    [_infoRows release];
    _infoRows = [rows retain];
    [self.tableView reloadData];
}

/* sections: the phone and the bio, the stories and gifts, the way out; the photo, the edit and the song are the rows of the header */
enum { SectionInfo, SectionLists, SectionSignOut, SectionCount };

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
    case SectionInfo: return (NSInteger)_infoRows.count;
    case SectionLists: return 5 + (_full.channel ? 1 : 0);
    default: return 1;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL channelRow = indexPath.section == SectionLists && indexPath.row == 5;
    NSString *identifier = indexPath.section == SectionInfo ? @"info" : (indexPath.section == SectionSignOut ? @"signout" : (channelRow ? @"channel" : @"row"));
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        Class cellClass = (indexPath.section == SectionInfo || channelRow) ? [NoshiClassicInfoCell class] : [UITableViewCell class];
        cell = [[[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        NoshiClassicStyleCell(cell);
        if (indexPath.section == SectionSignOut) {
            cell.textLabel.textAlignment = NoshiTextAlignmentCenter;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
        } else if (indexPath.section != SectionInfo) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    cell.accessoryView = nil;
    switch (indexPath.section) {
    case SectionInfo: {
        NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
        [(NoshiClassicInfoCell *)cell setValue:[row objectAtIndex:1] caption:[row objectAtIndex:0]];
        cell.imageView.image = [[row objectAtIndex:0] isEqualToString:NSLocalizedString(@"profile.stars", nil)] ? NoshiStarsGlyph(24) : nil;
        break;
    }
    case SectionLists: {
        NSString *keys[4] = {@"profile.tab.stories", @"profile.tab.archive", @"gifts.title", @"profile.qr"};
        if (indexPath.row < 4) cell.textLabel.text = NSLocalizedString(keys[indexPath.row], nil);
        else if (indexPath.row == 4) cell.textLabel.text = NSLocalizedString(@"music.title", nil);
        else {
            NoshiDialog *channel = _full.channel.dialog;
            NSArray *entities = nil;
            NSString *title = NoshiNameWithBadge([NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"profile.channel", nil), channel.title],
                                                   NoshiBadgeDocument(channel.emojiStatus, channel.premium), &entities);
            NoshiClassicInfoCell *info = (NoshiClassicInfoCell *)cell;
            [info setRowTitle:title entities:entities];
            if (channel.emojiStatus) {
                NoshiWeakReference *weak = [info weakReference];
                NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:channel.emojiStatus]], _session, _media, ^{
                    [[(NoshiClassicInfoCell *)weak.target valueLabel] setNeedsDisplay];
                });
            }
        }
        break;
    }
    default:
        cell.textLabel.text = NSLocalizedString(@"profile.signout", nil);
        cell.textLabel.textColor = _working ? [UIColor grayColor] : NoshiColorAccent();
        cell.accessoryView = _working ? _spinner : nil;
        if (_working) [_spinner startAnimating];
        break;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != SectionInfo) return tableView.rowHeight;
    NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
    BOOL stars = [[row objectAtIndex:0] isEqualToString:NSLocalizedString(@"profile.stars", nil)];
    return [NoshiClassicInfoCell heightForValue:[row objectAtIndex:1] caption:[row objectAtIndex:0] tableWidth:tableView.bounds.size.width hasImage:stars];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UINavigationController *navigation = self.navigationController;
    NoshiDialog *own = _person && _media ? [NoshiDialog savedMessagesWithPerson:_person] : nil;
    switch (indexPath.section) {
    case SectionInfo: {
        NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
        [UIPasteboard generalPasteboard].string = [row objectAtIndex:1];
        break;
    }
    case SectionLists:
        if (!own) break;
        if (indexPath.row == 3) {
            [navigation pushViewController:[[[NoshiProfileQrController alloc] initWithSession:_session person:_person avatars:_avatars media:_media] autorelease] animated:YES];
        } else if (indexPath.row == 4) {
            NoshiMusicListController *list = [[[NoshiMusicListController alloc] initWithSession:_session dialog:own first:_full.music avatars:_avatars media:_media] autorelease];
            [navigation pushViewController:list animated:YES];
        } else if (indexPath.row == 5) {
            [navigation pushViewController:[[[NoshiChatController alloc] initWithSession:_session dialog:_full.channel.dialog avatars:_avatars media:_media
                                                                                  stickers:_stickerLibrary] autorelease] animated:YES];
        } else if (indexPath.row == 2) {
            NoshiGiftsController *gifts = [[[NoshiGiftsController alloc] initWithSession:_session dialog:own mine:YES avatars:_avatars media:_media] autorelease];
            gifts.stickers = _stickerLibrary;
            [navigation pushViewController:gifts animated:YES];
        } else {
            NoshiProfileFeedKind kind = indexPath.row == 0 ? NoshiFeedPinnedStories : NoshiFeedArchivedStories;
            [navigation pushViewController:[[[NoshiStoryFeedController alloc] initWithSession:_session kind:kind owner:own avatars:_avatars media:_media] autorelease] animated:YES];
        }
        break;
    default:
        if (_working) return;
        [self confirmSignOut];
        break;
    }
}

- (void)choosePhoto {
    if (_uploading) return;
    NoshiWeakReference *me = _weak;
    [NoshiProfilePhotoPicker pickWithSheetIn:NoshiOverlayHost() picked:^(NSString *path, BOOL video) {
        NoshiClassicProfileController *profile = me.target;
        if (!profile) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [profile uploadPhotoAtPath:path video:video];
    } failed:^{
        NoshiShowNotice(nil, NSLocalizedString(@"attach.failed", nil));
    }];
}

- (void)uploadPhotoAtPath:(NSString *)path video:(BOOL)video {
    _uploading = YES;
    [self retain];
    void (^finished)(NSString *) = ^(NSString *errorName) {
        [self autorelease];
        _uploading = NO;
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (errorName) {
            NSLog(@"noshigram: profile %@ not set: %@", video ? @"video" : @"photo", errorName);
            return;
        }
        [self loadProfile];
        [_hero reloadPhotos];
    };
    if (video) [_session uploadProfileVideoAtPath:path completion:finished];
    else [_session uploadProfilePhotoAtPath:path completion:finished];
}

/* the question is the system alert in the middle of the screen: an action sheet on an ipad is a popover with nothing to point at, and it appeared in the middle of the chat beside the list */
- (void)confirmSignOut {
    if (_working || !_signOutHandler) return;
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"profile.signout.confirm", nil), NSLocalizedString(@"profile.signout", nil),
                         ^{ [(NoshiClassicProfileController *)weak.target signOutNow]; });
}

- (void)signOutNow {
    if (!_signOutHandler) return;
    _working = YES;
    [self.tableView reloadData];
    [self retain];
    _signOutHandler(^(NSString *errorName) {
        [self autorelease];
        _working = NO;
        [self.tableView reloadData];
        if (!errorName) return;
        Class alertClass = NSClassFromString(@"UIAlertView");
        id failure = [[alertClass alloc] initWithTitle:nil
                                               message:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                              delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [failure show];
        [failure release];
    });
}

@end
