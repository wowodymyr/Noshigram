#import <QuartzCore/QuartzCore.h>
#import "noshi_alert_view.h"
#import "noshi_community_controller.h"

#import "noshi_chat_controller.h"
#import "noshi_community.h"
#import "noshi_dialog_cell.h"
#import "noshi_draft.h"
#import "noshi_theme.h"
#import "noshi_topics_screen.h"

#define HEADER_HEIGHT 52.0
#define SIDE_MARGIN 16.0
/* the sections stand on rounded cards that keep this far from the edges of the screen, and a gap lies between two cards */
#define CARD_INSET 12.0
#define CARD_RADIUS 22.0
#define CARD_GAP 14.0
#define SWITCH_PAD 20.0

typedef enum { NoshiCardTop, NoshiCardMiddle, NoshiCardBottom, NoshiCardSingle } NoshiCardPart;

/* the piece of a card that one row or header stands on: the corners that touch the edge of the card are round, the others square */
@interface NoshiCardBackdrop : UIView {
    NoshiCardPart _part;
}
@property (nonatomic, assign) NoshiCardPart part;
@end

@implementation NoshiCardBackdrop
@synthesize part = _part;
- (void)setPart:(NoshiCardPart)part {
    _part = part;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIRectCorner corners = _part == NoshiCardTop ? (UIRectCornerTopLeft | UIRectCornerTopRight)
                         : _part == NoshiCardBottom ? (UIRectCornerBottomLeft | UIRectCornerBottomRight)
                         : _part == NoshiCardSingle ? UIRectCornerAllCorners : (UIRectCorner)0;
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds byRoundingCorners:corners cornerRadii:CGSizeMake(CARD_RADIUS, CARD_RADIUS)].CGPath;
    self.layer.mask = mask;
}
@end

static NoshiCardBackdrop *NoshiCardBackdropOf(NoshiCardPart part, UIColor *color) {
    NoshiCardBackdrop *view = [[[NoshiCardBackdrop alloc] init] autorelease];
    view.backgroundColor = color;
    view.part = part;
    return view;
}

/* a chat of the community on its card: the row is narrowed to the card, so everything the row draws keeps its own margins inside it */
@interface NoshiCommunityChatCell : NoshiDialogCell
@end

@implementation NoshiCommunityChatCell
- (void)setFrame:(CGRect)frame {
    [super setFrame:CGRectInset(frame, CARD_INSET, 0)];
}
@end

/* the switch and its words on a card of their own */
@interface NoshiCommunitySwitchCell : UITableViewCell {
    UILabel *_title;
    UILabel *_hint;
    UISwitch *_switch;
}
@property (nonatomic, readonly) UILabel *title;
@property (nonatomic, readonly) UILabel *hint;
@property (nonatomic, readonly) UISwitch *toggle;
+ (CGFloat)heightForHint:(NSString *)hint width:(CGFloat)width;
@end

@implementation NoshiCommunitySwitchCell
@synthesize title = _title;
@synthesize hint = _hint;
@synthesize toggle = _switch;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundView = NoshiCardBackdropOf(NoshiCardSingle, NoshiColorCard());
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.font = NoshiFontRegular(18);
    _title.textColor = NoshiColorTitle();
    [self.contentView addSubview:_title];
    _hint = [[UILabel alloc] init];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.font = NoshiFontRegular(15);
    _hint.textColor = NoshiColorSecondary();
    _hint.numberOfLines = 0;
    [self.contentView addSubview:_hint];
    _switch = [[UISwitch alloc] init];
    [self.contentView addSubview:_switch];
    return self;
}

- (void)dealloc {
    [_title release];
    [_hint release];
    [_switch release];
    [super dealloc];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:CGRectInset(frame, CARD_INSET, 0)];
}

+ (CGFloat)heightForHint:(NSString *)hint width:(CGFloat)width {
    UILabel *probe = [[[UILabel alloc] init] autorelease];
    probe.font = NoshiFontRegular(15);
    probe.numberOfLines = 0;
    probe.text = hint;
    CGFloat text = ceil([probe sizeThatFits:CGSizeMake(MAX(1, width - 2 * CARD_INSET - 2 * SWITCH_PAD), CGFLOAT_MAX)].height);
    return SWITCH_PAD + 32 + 12 + text + SWITCH_PAD;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGSize toggle = _switch.bounds.size;
    _switch.frame = CGRectMake(width - SWITCH_PAD - toggle.width, SWITCH_PAD + (32 - toggle.height) / 2, toggle.width, toggle.height);
    _title.frame = CGRectMake(SWITCH_PAD, SWITCH_PAD, MAX(0, width - 2 * SWITCH_PAD - toggle.width - 8), 32);
    CGSize hint = [_hint sizeThatFits:CGSizeMake(MAX(1, width - 2 * SWITCH_PAD), CGFLOAT_MAX)];
    _hint.frame = CGRectMake(SWITCH_PAD, SWITCH_PAD + 32 + 12, MAX(1, width - 2 * SWITCH_PAD), ceil(hint.height));
}
@end

enum { SectionSwitch, SectionJoined, SectionViewable, SectionCount };

@interface NoshiCommunityController () {
    NoshiDialog *_community;
    NSArray *_known;
    NoshiCommunity *_loaded;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    void (^_closeHandler)(void);
}
@end

@implementation NoshiCommunityController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(NoshiSession *)session community:(NoshiDialog *)community known:(NSArray *)known avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers {
    self = [super initWithSession:session];
    if (!self) return nil;
    _community = [community retain];
    _known = [known copy];
    _media = [media retain];
    _stickers = [stickers retain];
    self.avatars = avatars;
    self.heading = community.title;
    self.showsBack = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:) name:NoshiDraftDidChangeNotification object:session.drafts];
    return self;
}

- (void)draftChanged:(NSNotification *)note {
    (void)note;
    if (self.isViewLoaded && _loaded) [self.table reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiDraftDidChangeNotification object:nil];
    [_community release];
    [_known release];
    [_loaded release];
    [_media release];
    [_stickers release];
    [_closeHandler release];
    [super dealloc];
}

- (void)loadItemsWithCompletion:(NoshiListCompletion)completion {
    [self.session loadCommunity:_community knownDialogs:_known completion:^(NoshiCommunity *community, NSString *errorName) {
        completion(community ? [NSArray arrayWithObject:community] : nil, errorName);
    }];
}

- (void)didReceiveItems:(NSArray *)items {
    [_loaded release];
    _loaded = [[items objectAtIndex:0] retain];
    /* how many chats the community holds, the ones the account is in and the ones it may look at */
    NSUInteger total = _loaded.joined.count + _loaded.viewable.count;
    self.subheading = total ? [NSString stringWithFormat:NSLocalizedString(@"community.chats.count", nil), (unsigned long)total] : nil;
}

/* the switch row is always there once the community is in, so the list never reads as empty */
- (NSInteger)itemCount {
    return _loaded ? 1 : 0;
}

- (NSArray *)chatsOfSection:(NSInteger)section {
    return section == SectionJoined ? _loaded.joined : _loaded.viewable;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return _loaded ? SectionCount : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == SectionSwitch ? 1 : (NSInteger)[self chatsOfSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == SectionSwitch) return [NoshiCommunitySwitchCell heightForHint:NSLocalizedString(@"community.collapse.hint", nil) width:tableView.bounds.size.width];
    return [NoshiDialogCell rowHeight];
}

- (UILabel *)captionWithText:(NSString *)text font:(UIFont *)font {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = NoshiColorSecondary();
    label.font = font;
    label.numberOfLines = 0;
    label.text = text;
    return label;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section != SectionSwitch && [self chatsOfSection:section].count ? HEADER_HEIGHT : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == SectionSwitch || ![self chatsOfSection:section].count) return nil;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, HEADER_HEIGHT)] autorelease];
    /* the headers of a plain table stay at the top while the rows go on under them, so a clear one let the chats show through and the words lay on the words of a row */
    header.backgroundColor = NoshiColorScreen();
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    /* the title stands in the top of the card that holds the chats */
    NoshiCardBackdrop *card = NoshiCardBackdropOf(NoshiCardTop, NoshiColorCard());
    card.frame = CGRectMake(CARD_INSET, 0, header.bounds.size.width - 2 * CARD_INSET, HEADER_HEIGHT);
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:card];
    UILabel *label = [self captionWithText:NSLocalizedString(section == SectionJoined ? @"community.joined" : @"community.viewable", nil)
                                      font:NoshiFontSemibold(17)];
    label.frame = CGRectMake(SWITCH_PAD, 8, card.bounds.size.width - 2 * SWITCH_PAD, HEADER_HEIGHT - 8);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:label];
    return header;
}

/* the gap under a card, which keeps the next card apart; the switch card has no footer words since they stand inside it */
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == SectionSwitch || [self chatsOfSection:section].count ? CARD_GAP : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    UIView *gap = [[[UIView alloc] init] autorelease];
    gap.backgroundColor = NoshiColorScreen();
    return gap;
}

- (UITableViewCell *)switchCell:(UITableView *)tableView {
    static NSString *identifier = @"switch";
    NoshiCommunitySwitchCell *cell = (NoshiCommunitySwitchCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[NoshiCommunitySwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        [cell.toggle addTarget:self action:@selector(collapseChanged:) forControlEvents:UIControlEventValueChanged];
    }
    cell.title.text = NSLocalizedString(@"community.collapse", nil);
    cell.hint.text = NSLocalizedString(@"community.collapse.hint", nil);
    cell.toggle.on = _loaded.collapsed;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SectionSwitch) return [self switchCell:tableView];
    static NSString *identifier = @"chat";
    NoshiDialogCell *cell = (NoshiDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiCommunityChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    NSArray *chats = [self chatsOfSection:indexPath.section];
    /* the title above is the top of the card, so the first row is a middle one, and the last row closes the card */
    NoshiCardPart part = (NSUInteger)indexPath.row + 1 == chats.count ? NoshiCardBottom : NoshiCardMiddle;
    cell.backgroundView = NoshiCardBackdropOf(part, NoshiColorCard());
    cell.selectedBackgroundView = NoshiCardBackdropOf(part, NoshiColorField());
    NoshiDialog *chat = [chats objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithDialog:chat avatars:self.avatars action:NoshiDialogActionNone];
    [cell showDraft:NoshiVisibleDraft(self.session.drafts, chat)];
    [cell layoutIfNeeded];
    return cell;
}

- (void)collapseChanged:(UISwitch *)sender {
    BOOL collapsed = sender.on;
    _loaded.collapsed = collapsed;
    [self.session setCommunity:_community collapsed:collapsed completion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"noshigram: folding community %lld failed: %@", _community.peerId, errorName);
        /* the list keeps what the server has, so the switch goes back to it and the person is told */
        _loaded.collapsed = !collapsed;
        sender.on = !collapsed;
        Class alertClass = NoshiAlertClass();
        id alert = [[alertClass alloc] initWithTitle:nil message:[NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                            delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SectionSwitch) return;
    NoshiDialog *chat = [[self chatsOfSection:indexPath.section] objectAtIndex:(NSUInteger)indexPath.row];
    if (chat.forum) {
        [self.navigationController pushViewController:NoshiTopicsScreen(self.session, chat, self.avatars, _media, _stickers,
                                                                          ^{ [self reloadDiscardingRunning]; }) animated:YES];
        return;
    }
    NoshiChatController *screen = [[[NoshiChatController alloc] initWithSession:self.session dialog:chat avatars:self.avatars
                                                                              media:_media stickers:_stickers] autorelease];
    /* reading changed the counts of the chats, so they load again once the person is back */
    screen.closeHandler = ^{ [self reloadDiscardingRunning]; };
    [self.navigationController pushViewController:screen animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] && _closeHandler) _closeHandler();
}

@end
