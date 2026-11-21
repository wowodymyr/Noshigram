#import "noshi_name_badge.h"
#import "noshi_developers.h"
#import "noshi_search_controller.h"
#import "noshi_string_drawing.h"
#import "noshi_lite_mode.h"
#import "noshi_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_bar_button.h"
#import "noshi_download_log.h"
#import "noshi_search_history.h"
#import "noshi_chat_controller.h"
#import "noshi_community_screen.h"
#import "noshi_topics_screen.h"
#import "noshi_emoji_label.h"
#import "noshi_filter_bar.h"
#import "noshi_lottie_view.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_weak_reference.h"

#define BAR_HEIGHT 44.0
#define FIELD_HEIGHT 38.0
#define CHIPS_HEIGHT 44.0
#define ROW_HEIGHT 64.0
#define PEERS_HEIGHT 104.0
#define SECTION_HEIGHT 34.0
#define SERVER_DELAY 0.4

/* the order of the kinds as they stand on the strip */
typedef enum {
    NoshiSearchTabChats,
    NoshiSearchTabChannels,
    NoshiSearchTabApps,
    NoshiSearchTabPosts,
    NoshiSearchTabMedia,
    NoshiSearchTabDownloads,
    NoshiSearchTabLinks,
    NoshiSearchTabFiles,
    NoshiSearchTabMusic,
    NoshiSearchTabVoice,
    NoshiSearchTabCount
} NoshiSearchTab;

/* what stands on the screen: the people and the recent chats, a list of results, a wait, a failure, or the duck */
typedef enum { NoshiSearchStateStart, NoshiSearchStateResults, NoshiSearchStateLoading, NoshiSearchStateFailed, NoshiSearchStateEmpty, NoshiSearchStateHint } NoshiSearchState;

/* the lists that are kept on the phone answer at once, with no pause for the server */
static BOOL NoshiTabIsInstant(NSInteger tab) {
    return tab == NoshiSearchTabChats || tab == NoshiSearchTabChannels || tab == NoshiSearchTabApps || tab == NoshiSearchTabDownloads;
}

static BOOL NoshiTabIsLocal(NSInteger tab) {
    return tab == NoshiSearchTabChats || tab == NoshiSearchTabChannels || tab == NoshiSearchTabApps;
}

static noshi_search_kind NoshiServerKindOfTab(NSInteger tab) {
    switch (tab) {
    case NoshiSearchTabPosts: return NOSHI_SEARCH_POSTS;
    case NoshiSearchTabMedia: return NOSHI_SEARCH_MEDIA;
    case NoshiSearchTabLinks: return NOSHI_SEARCH_LINKS;
    case NoshiSearchTabFiles: return NOSHI_SEARCH_FILES;
    case NoshiSearchTabMusic: return NOSHI_SEARCH_MUSIC;
    default: return NOSHI_SEARCH_VOICE;
    }
}

/* a row of the results: a chat with a line under its name, and for a found message the day it was written */
@interface NoshiSearchCell : UITableViewCell {
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_subtitle;
    UILabel *_date;
    UIView *_line;
}
- (void)configureWithDialog:(NoshiDialog *)dialog showsDate:(BOOL)showsDate highlight:(NSString *)highlight avatars:(NoshiAvatarCache *)avatars;
@end

@implementation NoshiSearchCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = NoshiColorField();
    self.selectedBackgroundView = selected;
    _avatar = [[NoshiAvatarView alloc] init];
    [self.contentView addSubview:_avatar];
    _title = [[NoshiEmojiLabel alloc] init];
    _title.font = NoshiFontSemibold(16);
    _title.textColor = NoshiColorTitle();
    [self.contentView addSubview:_title];
    _subtitle = [[NoshiEmojiLabel alloc] init];
    _subtitle.font = NoshiFontRegular(14);
    _subtitle.textColor = NoshiColorSecondary();
    [self.contentView addSubview:_subtitle];
    _date = [[UILabel alloc] init];
    NoshiLabelFitToWidth(_date, 9);
    _date.backgroundColor = [UIColor clearColor];
    _date.font = NoshiFontRegular(12.5);
    _date.textColor = NoshiColorSecondary();
    _date.textAlignment = NoshiTextAlignmentRight;
    [self.contentView addSubview:_date];
    _line = [[UIView alloc] init];
    _line.backgroundColor = NoshiColorHairline();
    [self.contentView addSubview:_line];
    return self;
}

- (void)dealloc {
    [_avatar release];
    [_title release];
    [_subtitle release];
    [_date release];
    [_line release];
    [super dealloc];
}

/* the words that were looked for stand out in the line of a found message, as the other clients mark them */
static NSArray *NoshiSearchMarks(NSString *text, NSString *words) {
    if (!words.length || !text.length) return nil;
    NSMutableArray *marks = [NSMutableArray array];
    NSRange at = NSMakeRange(0, 0);
    while (marks.count < 8) {
        at = [text rangeOfString:words options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch range:NSMakeRange(NSMaxRange(at), text.length - NSMaxRange(at))];
        if (at.location == NSNotFound) break;
        [marks addObject:[[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleBold range:at url:nil] autorelease]];
    }
    return marks.count ? marks : nil;
}

- (void)configureWithDialog:(NoshiDialog *)dialog showsDate:(BOOL)showsDate highlight:(NSString *)highlight avatars:(NoshiAvatarCache *)avatars {
    _avatar.seed = dialog.avatarSeed;
    _avatar.initials = dialog.initials;
    _avatar.deleted = dialog.deleted;
    _avatar.accent = dialog.saved || dialog.replies;
    _avatar.showsSymbol = dialog.saved || dialog.replies;
    _avatar.symbol = dialog.replies ? NoshiSymbolReply : NoshiSymbolBookmark;
    [_avatar setPhoto:dialog.saved || dialog.replies ? nil : dialog.photo cache:avatars];
    /* the name wears the marks and the status of the person, as in the list of chats */
    NSArray *badges = nil;
    _title.dropsUndrawable = YES;
    _title.text = NoshiNameWithBadges(dialog.title, NoshiDialogBadgeDocument(dialog), NoshiDialogIsDeveloper(dialog), &badges);
    _title.entities = badges;
    _subtitle.text = dialog.preview;
    _subtitle.entities = NoshiSearchMarks(dialog.preview, highlight);
    _date.text = showsDate ? NoshiListTimeText(dialog.date) : @"";
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat hairline = 1.0 / NoshiScreenScale();
    _avatar.frame = CGRectMake(14, (ROW_HEIGHT - 48) / 2, 48, 48);
    CGFloat textX = 76;
    CGFloat dateWidth = _date.text.length ? 64 : 0;
    _date.frame = CGRectMake(width - 14 - dateWidth, 13, dateWidth, 18);
    _title.frame = CGRectMake(textX, 11, MAX(0, width - textX - 14 - (dateWidth ? dateWidth + 6 : 0)), 21);
    _subtitle.frame = CGRectMake(textX, 34, MAX(0, width - textX - 14), 19);
    _line.frame = CGRectMake(textX, ROW_HEIGHT - hairline, width - textX, hairline);
}

@end

/* the people on top: a sideways strip of round avatars with a first name under each */
@interface NoshiTopPeersView : UIScrollView {
    id _target;
}
@property (nonatomic, assign) id target;
- (void)setDialogs:(NSArray *)dialogs avatars:(NoshiAvatarCache *)avatars;
@end

@implementation NoshiTopPeersView

@synthesize target = _target;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.showsHorizontalScrollIndicator = NO;
    self.scrollsToTop = NO;
    return self;
}

- (void)setDialogs:(NSArray *)dialogs avatars:(NoshiAvatarCache *)avatars {
    for (UIView *view in [[self.subviews copy] autorelease]) [view removeFromSuperview];
    CGFloat x = 12;
    for (NSUInteger i = 0; i < dialogs.count; ++i) {
        NoshiDialog *dialog = [dialogs objectAtIndex:i];
        UIControl *item = [[[UIControl alloc] initWithFrame:CGRectMake(x, 10, 72, 84)] autorelease];
        item.tag = (NSInteger)i;
        [item addTarget:_target action:@selector(peerTapped:) forControlEvents:UIControlEventTouchUpInside];
        NoshiAvatarView *avatar = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(8, 0, 56, 56)] autorelease];
        avatar.seed = dialog.avatarSeed;
        avatar.initials = dialog.initials;
        avatar.deleted = dialog.deleted;
        avatar.circular = YES;
        avatar.userInteractionEnabled = NO;
        [avatar setPhoto:dialog.photo cache:avatars];
        [item addSubview:avatar];
        NoshiEmojiLabel *name = [[[NoshiEmojiLabel alloc] initWithFrame:CGRectMake(0, 61, 72, 18)] autorelease];
        name.font = NoshiFontRegular(12.5);
        name.textColor = NoshiColorTitle();
        name.textAlignment = NoshiTextAlignmentCenter;
        NSString *first = [[dialog.title componentsSeparatedByString:@" "] objectAtIndex:0];
        name.text = first;
        [item addSubview:name];
        [self addSubview:item];
        x += 76;
    }
    self.contentSize = CGSizeMake(x + 8, self.bounds.size.height);
}

@end

@interface NoshiSearchController () <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate, NoshiFilterBarDelegate> {
    NoshiSession *_session;
    NSArray *_dialogs;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;

    UITextField *_field;
    NoshiBarButton *_cancel;
    NoshiFilterBar *_tabs;
    UITableView *_table;
    NoshiTopPeersView *_peers;
    UIView *_emptyView;
    NoshiLottieView *_duck;
    UILabel *_emptyTitle;
    UILabel *_emptyText;
    UIActivityIndicatorView *_spinner;

    NSString *_query;
    NSArray *_rows;
    /* the public chats the server found for the text, shown under the local results on the chat kinds */
    NSArray *_global;
    /* the messages the server found in the chats, under the chats on the first kind, as the other clients list them */
    NSArray *_messages;
    BOOL _globalDone, _messagesDone, _globalFailed;
    NSArray *_recent;
    NoshiSearchState _state;
    NSUInteger _generation;
    CGFloat _keyboardOverlap;
    BOOL _observing;
    BOOL _focused;
}
@end

@implementation NoshiSearchController

- (id)initWithSession:(NoshiSession *)session dialogs:(NSArray *)dialogs avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialogs = [dialogs retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _query = [@"" copy];
    _rows = [[NSArray alloc] init];
    _recent = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _field.delegate = nil;
    _table.delegate = nil;
    _table.dataSource = nil;
    _tabs.delegate = nil;
    [_session release];
    [_dialogs release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_field release];
    [_cancel release];
    [_tabs release];
    [_table release];
    [_peers release];
    [_emptyView release];
    [_duck release];
    [_emptyTitle release];
    [_emptyText release];
    [_spinner release];
    [_query release];
    [_rows release];
    [_global release];
    [_messages release];
    [_recent release];
    [super dealloc];
}

#pragma mark recent

- (NSString *)recentKeyOf:(NoshiDialog *)dialog {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

- (void)loadRecent {
    [_recent release];
    _recent = [NoshiSearchHistoryDialogs(_session, _dialogs) retain];
}

- (void)remember:(NoshiDialog *)dialog {
    NoshiSearchHistoryRemember(_session, dialog, _dialogs);
}

- (void)clearRecent {
    NoshiSearchHistoryClear(_session);
    [self loadRecent];
    [self refreshState];
}


#pragma mark views

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _field = [[UITextField alloc] init];
    _field.backgroundColor = NoshiColorField();
    _field.layer.cornerRadius = FIELD_HEIGHT / 2;
    _field.delegate = self;
    _field.placeholder = NSLocalizedString(@"chats.search", nil);
    _field.font = NoshiFontRegular(16);
    _field.textColor = NoshiColorTitle();
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.returnKeyType = UIReturnKeySearch;
    _field.keyboardAppearance = NoshiThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    UIImageView *glass = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolMagnifier, 16, NoshiColorMuted())] autorelease];
    glass.contentMode = UIViewContentModeCenter;
    glass.frame = CGRectMake(0, 0, 38, FIELD_HEIGHT);
    _field.leftView = glass;
    _field.leftViewMode = UITextFieldViewModeAlways;
    [_field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    [root addSubview:_field];

    _cancel = [[NoshiBarButton alloc] init];
    _cancel.title = NSLocalizedString(@"picker.cancel", nil);
    [_cancel addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancel];

    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"search.tab.chats", nil), NSLocalizedString(@"search.tab.channels", nil),
                       NSLocalizedString(@"search.tab.apps", nil), NSLocalizedString(@"search.tab.posts", nil), NSLocalizedString(@"search.tab.media", nil),
                       NSLocalizedString(@"search.tab.downloads", nil), NSLocalizedString(@"search.tab.links", nil), NSLocalizedString(@"search.tab.files", nil),
                       NSLocalizedString(@"search.tab.music", nil), NSLocalizedString(@"search.tab.voice", nil), nil];
    _tabs = [[NoshiFilterBar alloc] initWithTitles:titles];
    _tabs.delegate = self;
    [root addSubview:_tabs];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    NoshiScrollViewOwnsInsets(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = ROW_HEIGHT;
    [root addSubview:_table];
    _peers = [[NoshiTopPeersView alloc] initWithFrame:CGRectMake(0, 0, 320, PEERS_HEIGHT)];
    _peers.target = self;

    _emptyView = [[UIView alloc] init];
    _emptyView.hidden = YES;
    [root addSubview:_emptyView];
    _duck = [[NoshiLottieView alloc] initWithAnimationNamed:@"search_empty"];
    [_emptyView addSubview:_duck];
    _emptyTitle = [[UILabel alloc] init];
    _emptyTitle.backgroundColor = [UIColor clearColor];
    _emptyTitle.textColor = NoshiColorTitle();
    _emptyTitle.textAlignment = NoshiTextAlignmentCenter;
    [_emptyView addSubview:_emptyTitle];
    _emptyText = [[UILabel alloc] init];
    _emptyText.backgroundColor = [UIColor clearColor];
    _emptyText.textColor = NoshiColorSecondary();
    _emptyText.textAlignment = NoshiTextAlignmentCenter;
    _emptyText.numberOfLines = 0;
    [_emptyView addSubview:_emptyText];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:NoshiThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadRecent];
    [self refreshState];
    [self loadEveryChat];
}

/* the list the screen was given holds one request of chats, and a chat further down would be found only by the server's own search, which keeps few of them */
- (void)loadEveryChat {
    NoshiWeakReference *weak = _weak;
    [_session loadRemainingDialogsAfter:_dialogs completion:^(NSArray *all) {
        NoshiSearchController *search = weak.target;
        if (!search || all.count <= search->_dialogs.count) return;
        [search->_dialogs release];
        search->_dialogs = [all retain];
        [search loadRecent];
        if (search->_query.length && NoshiTabIsLocal(search->_tabs.selectedIndex)) {
            ++search->_generation;
            [search runSearch];
        }
    }];
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

#pragma mark layout

- (void)layoutSearch {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    CGRect column = NoshiContentColumn(size, insets, NOSHI_COLUMN_LIST);
    CGFloat left = column.origin.x, width = column.size.width, edge = CGRectGetMaxX(column);
    CGFloat top = insets.top + 6;
    _field.frame = CGRectMake(left + 14, top, width - 28 - 76, FIELD_HEIGHT);
    /* the cancel stands on the line of the field; the button keeps 14 points of padding at its right end, the margin the field has on the left */
    _cancel.frame = CGRectMake(CGRectGetMaxX(_field.frame), top, edge - CGRectGetMaxX(_field.frame), FIELD_HEIGHT);
    CGFloat tabsY = insets.top + BAR_HEIGHT + 4;
    _tabs.frame = CGRectMake(left, tabsY, width, CHIPS_HEIGHT);
    CGFloat bodyY = tabsY + CHIPS_HEIGHT;
    CGFloat bodyHeight = MAX(0, size.height - _keyboardOverlap - bodyY);
    _table.frame = CGRectMake(left, bodyY, width, bodyHeight);
    _table.contentInset = UIEdgeInsetsMake(0, 0, _keyboardOverlap > 0 ? 0 : insets.bottom, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    _emptyView.frame = CGRectMake(left, bodyY, width, bodyHeight);
    _peers.frame = CGRectMake(0, 0, width, PEERS_HEIGHT);
    CGFloat block = 130 + 12 + 24 + 6 + 62;
    CGFloat y = MAX(8, (bodyHeight - block) / 2 - 20);
    _duck.frame = CGRectMake((width - 130) / 2, y, 130, 130);
    _emptyTitle.font = NoshiFontBold(19);
    _emptyTitle.frame = CGRectMake(24, y + 142, width - 48, 24);
    _emptyText.font = NoshiFontRegular(15);
    _emptyText.frame = CGRectMake(32, y + 172, width - 64, 62);
    CGPoint middle = CGPointMake(CGRectGetMidX(column), bodyY + bodyHeight / 2 - 20);
    _spinner.center = middle;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSearch];
}

#pragma mark keyboard

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    if (!_observing) {
        _observing = YES;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    }
    /* coming back from a chat shows the chats you opened lately, with the one you just opened first */
    /* the screen opens without a push, so it fades in and grows from a little larger, the way the search brings
       its results in */
    if (!_focused) {
        CGFloat scale = NoshiLiteEnabled(NOSHI_LITE_CHAT_SCALE) ? 1.04f : 1;
        NoshiAnimateEnter(self.view, CGAffineTransformMakeScale(scale, scale), 0, NOSHI_MOTION_ENTER);
    }
    [self loadRecent];
    /* a file that came while a chat was open is in the list when it is left */
    if (_tabs.selectedIndex == NoshiSearchTabDownloads) [self runSearch];
    else [_table reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* the keyboard comes up when the screen opens, not again when a chat opened from here is left */
    if (!_focused) {
        _focused = YES;
        [_field becomeFirstResponder];
    }
    [self updateDuck];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_duck setPlaying:NO];
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
    _keyboardOverlap = overlap;
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{ [self layoutSearch]; } completion:nil];
}

- (void)close {
    [_field resignFirstResponder];
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = 0.2;
    [self.navigationController.view.layer addAnimation:fade forKey:@"search"];
    [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark query

- (void)textChanged {
    NSString *text = [_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text isEqualToString:_query]) return;
    [_query release];
    _query = [text copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    ++_generation;
    if (NoshiTabIsInstant(_tabs.selectedIndex) || !_query.length) {
        [self runSearch];
        return;
    }
    /* the server is asked once the typing pauses, and what is on the screen waits meanwhile */
    _state = NoshiSearchStateLoading;
    [self refreshState];
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:SERVER_DELAY];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    (void)field;
    [self performSelector:@selector(textChanged) withObject:nil afterDelay:0];
    return YES;
}

- (void)filterBar:(NoshiFilterBar *)bar didSelectIndex:(NSInteger)index {
    (void)bar;
    (void)index;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    ++_generation;
    [self runSearch];
}

- (BOOL)dialog:(NoshiDialog *)dialog fitsTab:(NSInteger)tab {
    switch (tab) {
    case NoshiSearchTabChats: return dialog.kind == NOSHI_DIALOG_USER || dialog.kind == NOSHI_DIALOG_GROUP;
    case NoshiSearchTabChannels: return dialog.kind == NOSHI_DIALOG_CHANNEL;
    default: return dialog.kind == NOSHI_DIALOG_BOT;
    }
}

/* looks for the query on the kind of results the strip has selected */
- (void)runSearch {
    NSInteger tab = _tabs.selectedIndex;
    NSUInteger generation = _generation;
    [_rows release];
    _rows = [[NSArray alloc] init];
    [_global release];
    _global = nil;
    [_messages release];
    _messages = nil;
    _globalDone = _messagesDone = _globalFailed = NO;
    if (tab == NoshiSearchTabDownloads) {
        [_rows release];
        _rows = [NoshiDownloadLogDialogs(_session, _query) retain];
        _state = _rows.count ? NoshiSearchStateResults : (_query.length ? NoshiSearchStateEmpty : NoshiSearchStateHint);
    } else if (NoshiTabIsLocal(tab)) {
        NSMutableArray *found = [NSMutableArray array];
        for (NoshiDialog *dialog in _dialogs) {
            if (dialog.folder || ![self dialog:dialog fitsTab:tab]) continue;
            if (_query.length && [dialog.title rangeOfString:_query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
            [found addObject:dialog];
        }
        [_rows release];
        _rows = [found retain];
        /* with nothing local the screen waits for the server's public chats before it says there is nothing */
        _state = !_query.length ? NoshiSearchStateStart : (found.count ? NoshiSearchStateResults : NoshiSearchStateLoading);
        [self scheduleGlobal];
    } else if (!_query.length) {
        _state = NoshiSearchStateHint;
    } else {
        _state = NoshiSearchStateLoading;
        [self refreshState];
        NoshiWeakReference *weak = _weak;
        [_session searchGlobal:_query kind:NoshiServerKindOfTab(tab) offsetRate:0 completion:^(NSArray *dialogs, int32_t nextRate, NSString *errorName) {
            (void)nextRate;
            NoshiSearchController *search = weak.target;
            if (!search || generation != search->_generation) return;
            [search didSearch:dialogs error:errorName];
        }];
        return;
    }
    [self refreshState];
}

/* the server is asked for public chats once the typing pauses */
- (void)scheduleGlobal {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    if (_query.length) [self performSelector:@selector(runGlobal) withObject:nil afterDelay:SERVER_DELAY];
}

- (void)runGlobal {
    NSUInteger generation = _generation;
    NSInteger tab = _tabs.selectedIndex;
    NoshiWeakReference *weak = _weak;
    _messagesDone = tab != NoshiSearchTabChats;
    [_session searchPeers:_query completion:^(NSArray *dialogs, NSString *errorName) {
        NoshiSearchController *search = weak.target;
        if (!search || generation != search->_generation) return;
        [search didFindGlobal:dialogs forTab:tab error:errorName];
    }];
    /* the first kind also reads the messages of the chats, which is what the other clients list under the chats */
    if (tab == NoshiSearchTabChats) {
        [_session searchGlobal:_query kind:NOSHI_SEARCH_ALL offsetRate:0 completion:^(NSArray *dialogs, int32_t nextRate, NSString *errorName) {
            (void)nextRate;
            NoshiSearchController *search = weak.target;
            if (!search || generation != search->_generation) return;
            [search didFindMessages:dialogs error:errorName];
        }];
    }
}

/* what the screen says once the local rows and the answers of the server so far are in: the rows, a wait for the rest, or nothing found */
- (void)updateLocalState {
    BOOL any = _rows.count || _global.count || _messages.count;
    if (any) _state = NoshiSearchStateResults;
    else if (!_globalDone || !_messagesDone) _state = NoshiSearchStateLoading;
    else _state = _globalFailed ? NoshiSearchStateFailed : NoshiSearchStateEmpty;
    [self refreshState];
}

- (void)didFindGlobal:(NSArray *)dialogs forTab:(NSInteger)tab error:(NSString *)errorName {
    if (!dialogs) NSLog(@"noshigram: global search failed: %@", errorName);
    NSMutableSet *known = [NSMutableSet set];
    for (NoshiDialog *dialog in _rows) [known addObject:[self recentKeyOf:dialog]];
    NSMutableArray *fresh = [NSMutableArray array];
    for (NoshiDialog *dialog in dialogs) {
        if (![self dialog:dialog fitsTab:tab] || [known containsObject:[self recentKeyOf:dialog]]) continue;
        [fresh addObject:dialog];
    }
    [_global release];
    _global = fresh.count ? [fresh retain] : nil;
    _globalDone = YES;
    /* a failed server search with nothing local to show is a failure, not an empty answer */
    _globalFailed = !dialogs;
    [self updateLocalState];
}

- (void)didFindMessages:(NSArray *)dialogs error:(NSString *)errorName {
    if (!dialogs) NSLog(@"noshigram: message search failed: %@", errorName);
    [_messages release];
    _messages = dialogs.count ? [dialogs retain] : nil;
    _messagesDone = YES;
    [self updateLocalState];
}

- (void)didSearch:(NSArray *)dialogs error:(NSString *)errorName {
    if (!dialogs) {
        NSLog(@"noshigram: search failed: %@", errorName);
        _state = NoshiSearchStateFailed;
    } else {
        [_rows release];
        _rows = [dialogs retain];
        _state = dialogs.count ? NoshiSearchStateResults : NoshiSearchStateEmpty;
    }
    [self refreshState];
}

#pragma mark state

- (void)updateDuck {
    [_duck setPlaying:!_emptyView.hidden && !_duck.hidden && self.view.window != nil];
}

- (void)refreshState {
    BOOL showsEmpty = _state == NoshiSearchStateEmpty || _state == NoshiSearchStateHint || _state == NoshiSearchStateFailed;
    _emptyView.hidden = !showsEmpty;
    _duck.hidden = _state != NoshiSearchStateEmpty;
    if (_state == NoshiSearchStateEmpty) {
        _emptyTitle.text = NSLocalizedString(@"search.empty.title", nil);
        _emptyText.text = [NSString stringWithFormat:NSLocalizedString(@"search.empty.text", nil), _query];
    } else if (_state == NoshiSearchStateFailed) {
        _emptyTitle.text = @"";
        _emptyText.text = NSLocalizedString(@"search.failed", nil);
    } else if (_state == NoshiSearchStateHint) {
        BOOL downloads = _tabs.selectedIndex == NoshiSearchTabDownloads;
        _emptyTitle.text = downloads ? NSLocalizedString(@"search.downloads.title", nil) : @"";
        _emptyText.text = downloads ? NSLocalizedString(@"search.downloads.text", nil) : NSLocalizedString(@"search.hint", nil);
    }
    if (_state == NoshiSearchStateLoading) [_spinner startAnimating];
    else [_spinner stopAnimating];
    BOOL listed = _state == NoshiSearchStateResults || _state == NoshiSearchStateStart;
    _table.hidden = !listed;
    [self updateHeader];
    [_table reloadData];
    [self updateDuck];
    [self layoutSearch];
}

/* the people on top belong to the empty field on the chat kinds only */
- (void)updateHeader {
    BOOL showsPeers = _state == NoshiSearchStateStart && _tabs.selectedIndex == NoshiSearchTabChats;
    if (!showsPeers) {
        _table.tableHeaderView = nil;
        return;
    }
    NSMutableArray *people = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) {
        if (people.count >= 10) break;
        if (dialog.kind == NOSHI_DIALOG_USER && !dialog.saved && !dialog.folder) [people addObject:dialog];
    }
    if (!people.count) {
        _table.tableHeaderView = nil;
        return;
    }
    [_peers setDialogs:people avatars:_avatars];
    _table.tableHeaderView = _peers;
}

- (void)peerTapped:(UIControl *)item {
    NSMutableArray *people = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) {
        if (people.count >= 10) break;
        if (dialog.kind == NOSHI_DIALOG_USER && !dialog.saved && !dialog.folder) [people addObject:dialog];
    }
    if ((NSUInteger)item.tag < people.count) [self open:[people objectAtIndex:(NSUInteger)item.tag] remember:YES];
}

#pragma mark table

/* the recent chats are shown on the chat kinds they fit, the rest of the screen shows what the last search found */
- (NSArray *)visibleRows {
    if (_state != NoshiSearchStateStart) return _rows;
    NSMutableArray *fitting = [NSMutableArray array];
    for (NoshiDialog *dialog in _recent) if ([self dialog:dialog fitsTab:_tabs.selectedIndex]) [fitting addObject:dialog];
    return fitting;
}

/* the groups of the list from the top: the rows, then the public chats and the messages when the server found some; 0, 1 and 2 */
- (NSArray *)sectionKinds {
    NSMutableArray *kinds = [NSMutableArray arrayWithObject:[NSNumber numberWithInt:0]];
    if (_state != NoshiSearchStateResults) return kinds;
    if (_global.count) [kinds addObject:[NSNumber numberWithInt:1]];
    if (_messages.count && _tabs.selectedIndex == NoshiSearchTabChats) [kinds addObject:[NSNumber numberWithInt:2]];
    return kinds;
}

- (NSInteger)kindOfSection:(NSInteger)section {
    NSArray *kinds = [self sectionKinds];
    return (NSUInteger)section < kinds.count ? [[kinds objectAtIndex:(NSUInteger)section] integerValue] : 0;
}

- (NSArray *)itemsOfKind:(NSInteger)kind {
    return kind == 1 ? _global : (kind == 2 ? _messages : [self visibleRows]);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)[[self sectionKinds] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[self itemsOfKind:[self kindOfSection:section]] count];
}

- (NoshiDialog *)dialogAtIndexPath:(NSIndexPath *)indexPath {
    return [[self itemsOfKind:[self kindOfSection:indexPath.section]] objectAtIndex:(NSUInteger)indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ([self kindOfSection:section] != 0) return SECTION_HEIGHT;
    return _state == NoshiSearchStateStart && [[self visibleRows] count] ? SECTION_HEIGHT : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSInteger kind = [self kindOfSection:section];
    if (kind != 0) {
        UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, SECTION_HEIGHT)] autorelease];
        header.backgroundColor = NoshiColorField();
        UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(14, 0, tableView.bounds.size.width - 28, SECTION_HEIGHT)] autorelease];
        title.backgroundColor = [UIColor clearColor];
        title.font = NoshiFontSemibold(15);
        title.textColor = NoshiColorSecondary();
        title.text = NSLocalizedString(kind == 2 ? @"search.messages" : @"search.global", nil);
        [header addSubview:title];
        return header;
    }
    if (_state != NoshiSearchStateStart || ![[self visibleRows] count]) return nil;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, SECTION_HEIGHT)] autorelease];
    header.backgroundColor = NoshiColorField();
    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(14, 0, 200, SECTION_HEIGHT)] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.font = NoshiFontSemibold(15);
    title.textColor = NoshiColorAccent();
    title.text = NSLocalizedString(@"search.recent", nil);
    [header addSubview:title];
    UIButton *clear = [UIButton buttonWithType:UIButtonTypeCustom];
    clear.frame = CGRectMake(tableView.bounds.size.width - 110, 0, 100, SECTION_HEIGHT);
    clear.titleLabel.font = NoshiFontRegular(15);
    clear.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [clear setTitle:NSLocalizedString(@"search.clear", nil) forState:UIControlStateNormal];
    [clear setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clearRecent) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:clear];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"result";
    NoshiSearchCell *cell = (NoshiSearchCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiSearchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    BOOL message = ([self kindOfSection:indexPath.section] == 2) || (!NoshiTabIsLocal(_tabs.selectedIndex) && _state == NoshiSearchStateResults);
    [cell configureWithDialog:[self dialogAtIndexPath:indexPath] showsDate:message highlight:message ? _query : nil avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    /* a message found in a chat opens the chat at the message; the chat that was looked for is kept in the history */
    BOOL local = [self kindOfSection:indexPath.section] != 2 && (NoshiTabIsLocal(_tabs.selectedIndex) || _state == NoshiSearchStateStart);
    [self open:[self dialogAtIndexPath:indexPath] remember:local];
}

- (void)open:(NoshiDialog *)dialog remember:(BOOL)remember {
    [_field resignFirstResponder];
    if (remember) [self remember:dialog];
    if (remember && dialog.community) {
        [self.navigationController pushViewController:NoshiCommunityScreen(_session, dialog, nil, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    if (remember && dialog.forum) {
        [self.navigationController pushViewController:NoshiTopicsScreen(_session, dialog, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    if (!remember) chat.startMessageId = dialog.topMessage;
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    [_field resignFirstResponder];
}

@end
