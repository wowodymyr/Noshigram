#import "noshi_message_menu.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_avatar_view.h"
#import "noshi_person.h"
#import "noshi_dismiss_pan.h"
#import "noshi_blur.h"
#import "noshi_classic_chrome.h"
#import "noshi_emoji_label.h"
#import "noshi_lottie_view.h"
#import "noshi_reaction_artwork.h"
#import "noshi_weak_reference.h"
#import "noshi_platform.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"
#include "noshi_reaction_layout.h"

/* the menu of a message of telegram for ios 4: the chat goes dim, a black strip with an arrow stands over the message with the actions of one tap, and a white sheet of
   buttons rises from the bottom with the rest, as the TGMenuView and the TGMenuSheet of that app drew them */
#define BAR_HEIGHT 41.0
#define BAR_ARROW_WIDTH 20.0
#define BAR_ARROW_HEIGHT 10.0
#define BAR_RADIUS 8.0
#define BAR_BUTTON_PAD 17.0
#define SHEET_EDGE 10.0
#define SHEET_RADIUS 14.5
#define SHEET_ROW 57.0
#define SHEET_LINE 44.0
#define PILL_ITEM 42.0
#define REACTIONS_SHOWN 7
#define GAP 8.0

@implementation NoshiMenuItem

@synthesize title = _title;
@synthesize symbol = _symbol;
@synthesize tag = _tag;
@synthesize destructive = _destructive;

+ (NoshiMenuItem *)itemWithTitle:(NSString *)title symbol:(NoshiSymbol)symbol tag:(NSUInteger)tag destructive:(BOOL)destructive {
    NoshiMenuItem *item = [[[NoshiMenuItem alloc] init] autorelease];
    item.title = title;
    item.symbol = symbol;
    item.tag = tag;
    item.destructive = destructive;
    return item;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

@end

@interface NoshiMessageMenu () {
    NSArray *_rows;
    NSArray *_icons;
    NSArray *_reactions;
    NSString *_headerText;
    BOOL _headerRead;
    BOOL _closing;
    UIControl *_dim;
    UIView *_litClip;
    UIImageView *_lit;
    CGRect _litOriginalFrame;
    CGFloat _litShift;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    /* the black strip over the message and the white sheet at the bottom */
    UIView *_bar;
    UIView *_sheet;
    /* the parts of the header that a late answer changes in place, so the card does not have to be built again while it is still coming in */
    UIImageView *_headerMark;
    UILabel *_headerLabel;
    UIView *_headerView;
    BOOL _shown;
    CGRect _bubble;
    BOOL _outgoing;
    void (^_pickHandler)(NSUInteger tag);
    void (^_reactionHandler)(NoshiReaction *reaction);
    void (^_moreReactionsHandler)(void);
    void (^_dismissHandler)(void);
    void (^_headerHandler)(void);
    NSArray *_headerPeople;
    NoshiAvatarCache *_headerCache;
    /* the line under it that counts the reactions of the message, with the first of those who reacted at its right end */
    NSString *_reactorsText;
    NSArray *_reactorsPeople;
    void (^_reactorsHandler)(void);
}
@end

@implementation NoshiMessageMenu

@synthesize rows = _rows;
@synthesize icons = _icons;
@synthesize pickHandler = _pickHandler;
@synthesize reactionHandler = _reactionHandler;
@synthesize moreReactionsHandler = _moreReactionsHandler;
@synthesize dismissHandler = _dismissHandler;
@synthesize headerHandler = _headerHandler;
@synthesize reactorsHandler = _reactorsHandler;
@synthesize media = _media;

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_media release];
    [_rows release];
    [_icons release];
    [_reactions release];
    [_headerText release];
    [_dim release];
    [_lit release];
    [_litClip release];
    [_bar release];
    [_sheet release];
    [_headerMark release];
    [_headerLabel release];
    [_headerView release];
    [_pickHandler release];
    [_reactionHandler release];
    [_moreReactionsHandler release];
    [_dismissHandler release];
    [_headerHandler release];
    [_headerPeople release];
    [_headerCache release];
    [_reactorsText release];
    [_reactorsPeople release];
    [_reactorsHandler release];
    [super dealloc];
}

#pragma mark colors

static UIColor *NoshiSheetGround(void) { return NoshiThemeIsDark() ? [UIColor colorWithRed:0.11 green:0.11 blue:0.114 alpha:1] : [UIColor whiteColor]; }
static UIColor *NoshiSheetLine(void) { return NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.1] : [UIColor colorWithRed:0.784 green:0.78 blue:0.8 alpha:1]; }
static UIColor *NoshiSheetPress(void) { return NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithRed:0.922 green:0.922 blue:0.922 alpha:1]; }
static UIColor *NoshiSheetRed(void) { return [UIColor colorWithRed:1 green:0.231 blue:0.188 alpha:1]; }

#pragma mark content

- (void)setHeaderText:(NSString *)text read:(BOOL)read {
    BOOL hadHeader = _headerText.length > 0;
    [_headerText release];
    _headerText = [text copy];
    _headerRead = read;
    if (!_sheet) return;
    /* the same line with other words keeps the sheet as it is; only a line that appears or goes needs the rows moved */
    if (hadHeader && _headerText.length && _headerLabel) {
        _headerLabel.text = _headerText;
        _headerMark.image = NoshiCheckImage(_headerRead, 16, NoshiColorSecondary());
        [self placeMark:_headerMark label:_headerLabel inLine:_headerView faces:MIN(_headerPeople.count, (NSUInteger)3)];
        if (_headerHandler && ![_headerView viewWithTag:1]) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.tag = 1;
            button.frame = _headerView.bounds;
            button.accessibilityLabel = _headerText;
            [button addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
            [_headerView addSubview:button];
        }
        return;
    }
    [self rebuild];
}

- (void)setHeaderPeople:(NSArray *)people cache:(NoshiAvatarCache *)cache {
    [_headerPeople release];
    _headerPeople = [people copy];
    [_headerCache release];
    _headerCache = [cache retain];
    if (_sheet && _headerText.length) [self rebuild];
}

- (void)setReactorsText:(NSString *)text {
    [_reactorsText release];
    _reactorsText = [text copy];
    if (_sheet) [self rebuild];
}

- (void)setReactorsPeople:(NSArray *)people cache:(NoshiAvatarCache *)cache {
    [_reactorsPeople release];
    _reactorsPeople = [people copy];
    [_headerCache release];
    _headerCache = [cache retain];
    if (_sheet && _reactorsText.length) [self rebuild];
}

- (void)setReactions:(NSArray *)reactions {
    [_reactions release];
    _reactions = [reactions copy];
    if (_sheet) [self rebuild];
}

#pragma mark the black strip

- (void)barDown:(UIButton *)button { button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25]; }
- (void)barUp:(UIButton *)button { button.backgroundColor = [UIColor clearColor]; }

/* the strip of one-tap actions: white words on a black rounded plate with thin lines between them, and an arrow toward the message; the arrow is drawn at the bottom when the
   strip stands over the message and at the top when it stands under it */
- (UIView *)buildBarPointingDown:(BOOL)down {
    UIFont *font = [UIFont systemFontOfSize:14];
    CGFloat width = 0;
    NSMutableArray *widths = [NSMutableArray array];
    for (NoshiMenuItem *item in _icons) {
        CGFloat each = ceil(NoshiStringSize(item.title, font).width) + 2 * BAR_BUTTON_PAD;
        [widths addObject:[NSNumber numberWithDouble:each]];
        width += each;
    }
    CGFloat room = self.bounds.size.width - 2 * SHEET_EDGE;
    CGFloat squeeze = width > room ? room / width : 1;
    width = MIN(width, room);
    UIView *bar = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, BAR_HEIGHT + BAR_ARROW_HEIGHT)] autorelease];
    UIView *plate = [[[UIView alloc] initWithFrame:CGRectMake(0, down ? 0 : BAR_ARROW_HEIGHT, width, BAR_HEIGHT)] autorelease];
    plate.backgroundColor = [UIColor colorWithWhite:0 alpha:0.86];
    plate.layer.cornerRadius = BAR_RADIUS;
    plate.clipsToBounds = YES;
    plate.tag = 2;
    [bar addSubview:plate];
    CGFloat x = 0;
    for (NSUInteger i = 0; i < _icons.count; ++i) {
        NoshiMenuItem *item = [_icons objectAtIndex:i];
        CGFloat each = floor([[widths objectAtIndex:i] doubleValue] * squeeze);
        if (i == _icons.count - 1) each = width - x;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(x, 0, each, BAR_HEIGHT);
        button.tag = (NSInteger)item.tag;
        button.titleLabel.font = font;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        [button setTitle:item.title forState:UIControlStateNormal];
        [button setTitleColor:item.destructive ? NoshiSheetRed() : [UIColor whiteColor] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(barDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(barUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [plate addSubview:button];
        if (i > 0) {
            UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(x, 0, 1.0f / NoshiScreenScale(), BAR_HEIGHT)] autorelease];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
            line.userInteractionEnabled = NO;
            [plate addSubview:line];
        }
        x += each;
    }
    /* the arrow is a triangle in the color of the plate, set where the message is by the layout */
    CAShapeLayer *arrow = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (down) {
        [path moveToPoint:CGPointMake(0, 0)];
        [path addLineToPoint:CGPointMake(BAR_ARROW_WIDTH, 0)];
        [path addLineToPoint:CGPointMake(BAR_ARROW_WIDTH / 2, BAR_ARROW_HEIGHT)];
    } else {
        [path moveToPoint:CGPointMake(0, BAR_ARROW_HEIGHT)];
        [path addLineToPoint:CGPointMake(BAR_ARROW_WIDTH, BAR_ARROW_HEIGHT)];
        [path addLineToPoint:CGPointMake(BAR_ARROW_WIDTH / 2, 0)];
    }
    [path closePath];
    arrow.path = path.CGPath;
    arrow.fillColor = [UIColor colorWithWhite:0 alpha:0.86].CGColor;
    arrow.frame = CGRectMake(0, down ? BAR_HEIGHT : 0, BAR_ARROW_WIDTH, BAR_ARROW_HEIGHT);
    arrow.name = @"arrow";
    [bar.layer addSublayer:arrow];
    return bar;
}

#pragma mark the white sheet

- (void)sheetDown:(UIButton *)row { row.backgroundColor = NoshiSheetPress(); }
- (void)sheetUp:(UIButton *)row { row.backgroundColor = [UIColor clearColor]; }

- (UIView *)lineOfWidth:(CGFloat)width atY:(CGFloat)y {
    UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(0, y, width, 1.0f / NoshiScreenScale())] autorelease];
    line.backgroundColor = NoshiSheetLine();
    line.userInteractionEnabled = NO;
    return line;
}

/* a button of the sheet: its title in the middle, in the accent or in red */
- (UIButton *)sheetRowForItem:(NoshiMenuItem *)item width:(CGFloat)width {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, 0, width, SHEET_ROW);
    row.tag = (NSInteger)item.tag;
    row.titleLabel.font = [UIFont systemFontOfSize:20];
    row.titleLabel.adjustsFontSizeToFitWidth = YES;
    row.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [row setTitle:item.title forState:UIControlStateNormal];
    [row setTitleColor:item.destructive ? NoshiSheetRed() : NoshiColorAccent() forState:UIControlStateNormal];
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    [row addTarget:self action:@selector(sheetDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [row addTarget:self action:@selector(sheetUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return row;
}

/* the mark and the words of a line stand together in its middle, as wide as the words need and no wider than the room the faces at the right end leave; the words come later
   than the line for the time of reading, so this runs again when they change, or the label kept the width of the first words and shrank the new ones to nothing */
- (void)placeMark:(UIImageView *)mark label:(UILabel *)label inLine:(UIView *)line faces:(NSUInteger)faces {
    CGFloat width = line.bounds.size.width;
    CGFloat facesWidth = faces ? 22 + (CGFloat)(faces - 1) * 14 : 0;
    CGFloat textWidth = MIN(ceil(NoshiStringSize(label.text, label.font).width), width - 2 * 16 - 24 - (faces ? 2 * (facesWidth + 8) : 0));
    CGSize markSize = mark.image.size;
    CGFloat markWidth = mark.image ? markSize.width + 6 : 0;
    CGFloat startX = floor((width - textWidth - markWidth) / 2);
    mark.frame = CGRectMake(startX, floor((SHEET_LINE - markSize.height) / 2), markSize.width, markSize.height);
    label.frame = CGRectMake(startX + markWidth, 0, MAX(0, textWidth), SHEET_LINE);
}

/* a small grey line of the top of the sheet: a mark, a text in the middle, and at the right end the first three faces, each over the edge of the one before; a tap runs action */
- (UIView *)infoLineWithMark:(UIImage *)markImage text:(NSString *)text people:(NSArray *)people action:(SEL)action width:(CGFloat)width
                     outMark:(UIImageView **)outMark outLabel:(UILabel **)outLabel {
    UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, SHEET_LINE)] autorelease];
    NSUInteger faces = MIN(people.count, (NSUInteger)3);
    CGFloat faceSide = 22, faceStep = 14;
    CGFloat facesWidth = faces ? faceSide + (CGFloat)(faces - 1) * faceStep : 0;
    UIImageView *mark = [[[UIImageView alloc] initWithImage:markImage] autorelease];
    [line addSubview:mark];
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = NoshiColorSecondary();
    label.text = text;
    /* a line too long for the room ends in dots; shrinking it made it unreadable */
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [line addSubview:label];
    [self placeMark:mark label:label inLine:line faces:faces];
    for (NSUInteger i = 0; i < faces; ++i) {
        NoshiPerson *person = [people objectAtIndex:i];
        NoshiAvatarView *face = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(width - 14 - facesWidth + (CGFloat)i * faceStep, (SHEET_LINE - faceSide) / 2, faceSide, faceSide)] autorelease];
        face.seed = (NSUInteger)(person.userId % 1000003);
        face.initials = person.initials;
        face.deleted = person.deleted;
        face.userInteractionEnabled = NO;
        [face setPhoto:person.photo cache:_headerCache];
        [line addSubview:face];
    }
    if (action) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = 1;
        button.frame = line.bounds;
        button.accessibilityLabel = text;
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(sheetDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(sheetUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [line insertSubview:button atIndex:0];
    }
    if (outMark) *outMark = mark;
    if (outLabel) *outLabel = label;
    return line;
}

/* the reactions of the pill pop in together with the animation the server keeps for each; the still icon stays under it until its
   first frame is drawn and comes back when it has played, and the lottie view leaves as soon as it is done, since a parsed animation costs a few megabytes */
#define APPEAR_SIDE 30.0
/* a reaction under a finger grows by this much */
#define PRESS_SCALE 1.22

- (void)playAppearOfReaction:(NoshiReaction *)reaction inButton:(UIButton *)button label:(UIView *)label {
    if (reaction.row.kind != NOSHI_REACTION_EMOJI || !_media || NoshiReduceMotionEnabled()) return;
    NoshiReactionArtwork *artwork = [NoshiReactionArtwork artForEmoji:reaction.emoji];
    if (!artwork) return;
    [NoshiReactionArtwork attachStillOfArtwork:artwork toButton:button side:APPEAR_SIDE media:_media];
    if (!_weak) _weak = [[NoshiWeakReference referenceTo:self] retain];
    NoshiWeakReference *weak = _weak;
    [NoshiReactionArtwork animationViewForDocument:artwork.appear media:_media completion:^(NoshiLottieView *view) {
        NoshiMessageMenu *menu = weak.target;
        if (!view || !menu || menu->_closing || !button.superview) return;
        view.userInteractionEnabled = NO;
        view.frame = CGRectMake(floor((button.bounds.size.width - APPEAR_SIDE) / 2), floor((button.bounds.size.height - APPEAR_SIDE) / 2), APPEAR_SIDE, APPEAR_SIDE);
        view.hidden = YES;
        [button addSubview:view];
        __block NoshiLottieView *playing = view;
        view.firstFrameHandler = ^{ playing.hidden = NO; label.hidden = YES; [button viewWithTag:NOSHI_REACTION_STILL_TAG].hidden = YES; };
        view.finishHandler = ^{ [playing removeFromSuperview]; [NoshiReactionArtwork showRestingViewInButton:button]; };
        [view playOnce];
    }];
}

/* the reaction under the finger swells, and settles back when the finger lifts or leaves it */
- (void)reactionDown:(UIButton *)button {
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ button.transform = CGAffineTransformMakeScale(PRESS_SCALE, PRESS_SCALE); } completion:nil];
}

- (void)reactionUp:(UIButton *)button {
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.16 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ button.transform = CGAffineTransformIdentity; } completion:nil];
}

/* the reactions stand in one row at the top of the sheet: the first of them, and an arrow that opens the whole list */
- (UIView *)reactionsRowOfWidth:(CGFloat)width {
    CGFloat arrow = 36;
    NSUInteger shown = MIN(_reactions.count, (NSUInteger)REACTIONS_SHOWN);
    shown = MIN(shown, (NSUInteger)floor((width - 2 * 10 - arrow - 6) / PILL_ITEM));
    UIView *row = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, SHEET_ROW)] autorelease];
    CGFloat used = (CGFloat)shown * PILL_ITEM + 6 + arrow;
    CGFloat x = floor((width - used) / 2);
    for (NSUInteger i = 0; i < shown; ++i) {
        NoshiReaction *reaction = [_reactions objectAtIndex:i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(x + (CGFloat)i * PILL_ITEM, (SHEET_ROW - PILL_ITEM) / 2, PILL_ITEM, PILL_ITEM);
        button.tag = (NSInteger)i;
        button.layer.cornerRadius = PILL_ITEM / 2;
        if (reaction.chosen) button.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:0.25];
        button.accessibilityLabel = reaction.displayText;
        [button addTarget:self action:@selector(reactionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(reactionDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(reactionUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        NoshiEmojiLabel *label = [[[NoshiEmojiLabel alloc] init] autorelease];
        label.text = reaction.displayText;
        label.entities = reaction.displayEntities;
        label.font = NoshiFontRegular(27);
        label.textAlignment = NoshiTextAlignmentCenter;
        label.frame = button.bounds;
        label.userInteractionEnabled = NO;
        label.tag = NOSHI_REACTION_LABEL_TAG;
        [button addSubview:label];
        [row addSubview:button];
        [self playAppearOfReaction:reaction inButton:button label:label];
    }
    UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
    more.frame = CGRectMake(x + (CGFloat)shown * PILL_ITEM + 6, (SHEET_ROW - arrow) / 2, arrow, arrow);
    more.layer.cornerRadius = arrow / 2;
    more.backgroundColor = NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.12] : [UIColor colorWithWhite:0 alpha:0.06];
    [more setImage:NoshiSymbolImage(NoshiSymbolChevronRight, 18, NoshiColorSecondary()) forState:UIControlStateNormal];
    more.imageView.transform = CGAffineTransformMakeRotation(M_PI_2);
    more.accessibilityLabel = NSLocalizedString(@"chat.reactions", nil);
    [more addTarget:self action:@selector(moreReactionsTapped) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:more];
    return row;
}

/* the sheet: the reactions and the lines about the message on top, then a button for each action, all on one white plate with rounded corners that scrolls when it is taller
   than the room */
- (UIView *)buildSheetWithMaxHeight:(CGFloat)maxHeight {
    CGFloat width = MIN(self.bounds.size.width - 2 * SHEET_EDGE, 400);
    UIView *content = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)] autorelease];
    CGFloat y = 0;
    [_headerMark release];
    [_headerLabel release];
    [_headerView release];
    _headerMark = nil;
    _headerLabel = nil;
    _headerView = nil;
    if (_reactions.count) {
        UIView *row = [self reactionsRowOfWidth:width];
        row.frame = CGRectMake(0, y, width, SHEET_ROW);
        [content addSubview:row];
        y += SHEET_ROW;
    }
    if (_headerText.length) {
        if (y > 0) [content addSubview:[self lineOfWidth:width atY:y]];
        UIImageView *mark = nil;
        UILabel *label = nil;
        UIView *line = [self infoLineWithMark:NoshiCheckImage(_headerRead, 16, NoshiColorSecondary()) text:_headerText people:_headerPeople
                                       action:_headerHandler ? @selector(headerTapped) : NULL width:width outMark:&mark outLabel:&label];
        line.frame = CGRectMake(0, y, width, SHEET_LINE);
        _headerView = [line retain];
        _headerMark = [mark retain];
        _headerLabel = [label retain];
        [content addSubview:line];
        y += SHEET_LINE;
    }
    if (_reactorsText.length) {
        if (y > 0) [content addSubview:[self lineOfWidth:width atY:y]];
        UIView *line = [self infoLineWithMark:NoshiSymbolImage(NoshiSymbolHeartOutline, 16, NoshiColorSecondary()) text:_reactorsText people:_reactorsPeople
                                       action:_reactorsHandler ? @selector(reactorsTapped) : NULL width:width outMark:NULL outLabel:NULL];
        line.frame = CGRectMake(0, y, width, SHEET_LINE);
        [content addSubview:line];
        y += SHEET_LINE;
    }
    for (NoshiMenuItem *item in _rows) {
        if (y > 0) [content addSubview:[self lineOfWidth:width atY:y]];
        UIButton *row = [self sheetRowForItem:item width:width];
        row.frame = CGRectMake(0, y, width, SHEET_ROW);
        [content insertSubview:row atIndex:0];
        y += SHEET_ROW;
    }
    content.frame = CGRectMake(0, 0, width, y);
    UIView *sheet = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, MIN(y, maxHeight))] autorelease];
    sheet.backgroundColor = NoshiSheetGround();
    sheet.layer.cornerRadius = SHEET_RADIUS;
    sheet.clipsToBounds = YES;
    UIScrollView *scroll = [[[UIScrollView alloc] initWithFrame:sheet.bounds] autorelease];
    scroll.contentSize = content.bounds.size;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.bounces = y > maxHeight;
    scroll.delaysContentTouches = NO;
    [scroll addSubview:content];
    [sheet addSubview:scroll];
    return sheet;
}

#pragma mark layout

/* the sheet sits at the bottom; the lit message moves up so it stands over the sheet, and the strip goes over the message, or under it when the bar above leaves no room */
- (void)layout {
    CGSize size = self.bounds.size;
    CGFloat sheetHeight = _sheet ? _sheet.frame.size.height : 0;
    CGFloat sheetY = size.height - SHEET_EDGE - sheetHeight;
    _sheet.frame = CGRectMake(floor((size.width - _sheet.frame.size.width) / 2), sheetY, _sheet.frame.size.width, sheetHeight);
    CGFloat top = SHEET_EDGE;
    CGFloat limit = (_sheet ? sheetY : size.height) - GAP;
    CGFloat shift = 0;
    if (CGRectGetMaxY(_bubble) > limit) shift = limit - CGRectGetMaxY(_bubble);
    /* a tall message keeps its top in view, with room for the strip over it */
    CGFloat lowestTop = top + BAR_HEIGHT + BAR_ARROW_HEIGHT;
    if (CGRectGetMinY(_bubble) + shift < lowestTop) shift = MIN(0, lowestTop - CGRectGetMinY(_bubble));
    [self moveLitBy:shift];
    CGRect bubble = CGRectOffset(_bubble, 0, shift);
    if (!_bar) return;
    BOOL down = CGRectGetMinY(bubble) - BAR_HEIGHT - BAR_ARROW_HEIGHT >= top;
    CGFloat barWidth = _bar.frame.size.width;
    CGFloat center = CGRectGetMidX(bubble);
    CGFloat barX = MIN(MAX(SHEET_EDGE, floor(center - barWidth / 2)), size.width - SHEET_EDGE - barWidth);
    CGFloat barY = down ? CGRectGetMinY(bubble) - BAR_HEIGHT - BAR_ARROW_HEIGHT : MIN(CGRectGetMaxY(bubble), limit - BAR_HEIGHT - BAR_ARROW_HEIGHT);
    _bar.frame = CGRectMake(barX, MAX(top, barY), barWidth, BAR_HEIGHT + BAR_ARROW_HEIGHT);
    for (CALayer *layer in _bar.layer.sublayers) {
        if (![layer.name isEqualToString:@"arrow"]) continue;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CGFloat arrowX = MIN(MAX(BAR_RADIUS, center - barX - BAR_ARROW_WIDTH / 2), barWidth - BAR_RADIUS - BAR_ARROW_WIDTH);
        layer.frame = CGRectMake(arrowX, layer.frame.origin.y, BAR_ARROW_WIDTH, BAR_ARROW_HEIGHT);
        [CATransaction commit];
    }
}

/* the lit copy of the message moves by the shift the layout asks for; once the menu is up it slides there, and it slides back when the menu goes, so the message never jumps
   between the lit copy and the one in the list */
- (void)moveLitBy:(CGFloat)shift {
    if (!_lit) return;
    BOOL changed = shift != _litShift;
    _litShift = shift;
    CGRect target = CGRectOffset(_litOriginalFrame, 0, shift);
    if (!_shown || !changed || NoshiReduceMotionEnabled()) {
        _litClip.frame = target;
        return;
    }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{ _litClip.frame = target; } completion:nil];
}

/* the strip points down at the message when there is room over it, which is known only once the sheet is placed, so it is built after a first layout */
- (void)rebuild {
    [_sheet removeFromSuperview];
    [_sheet release];
    _sheet = nil;
    if (_rows.count || _reactions.count || _headerText.length || _reactorsText.length) {
        _sheet = [[self buildSheetWithMaxHeight:MAX(SHEET_ROW * 2, floor(self.bounds.size.height * 0.55))] retain];
        [self addSubview:_sheet];
        NoshiAddDismissPan(_sheet, self, @selector(dismiss));
    }
    [_bar removeFromSuperview];
    [_bar release];
    _bar = nil;
    [self layout];
    if (_icons.count) {
        CGRect bubble = CGRectOffset(_bubble, 0, _litShift);
        BOOL down = CGRectGetMinY(bubble) - BAR_HEIGHT - BAR_ARROW_HEIGHT >= SHEET_EDGE;
        _bar = [[self buildBarPointingDown:down] retain];
        [self addSubview:_bar];
        [self layout];
    }
}

#pragma mark show and close

- (void)showInView:(UIView *)host bubble:(CGRect)bubble outgoing:(BOOL)outgoing snapshot:(UIImage *)snapshot snapshotFrame:(CGRect)snapshotFrame clip:(CGRect)clip {
    if (self.superview) return;
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _bubble = bubble;
    _outgoing = outgoing;
    _dim = [[UIControl alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dim];
    if (snapshot) {
        /* only the bubble stays lit: the picture of the row holds the wallpaper beside it too, which the dim must cover; the window of the bubble moves with the layout,
           and the part of the bubble the list shows is what stays lit of a taller one */
        CGRect window = CGRectIntersection(CGRectInset(bubble, -3, -3), CGRectIntersection(clip, self.bounds));
        if (CGRectIsNull(window)) window = CGRectZero;
        _litClip = [[UIView alloc] initWithFrame:window];
        _litClip.clipsToBounds = YES;
        _litClip.userInteractionEnabled = NO;
        _lit = [[UIImageView alloc] initWithImage:snapshot];
        _lit.frame = CGRectOffset(snapshotFrame, -window.origin.x, -window.origin.y);
        _litOriginalFrame = window;
        [_litClip addSubview:_lit];
        [self addSubview:_litClip];
    }
    [self rebuild];
    [host addSubview:self];
    BOOL still = NoshiReduceMotionEnabled();
    if (_lit && _litShift != 0 && !still) {
        CGRect target = _litClip.frame;
        _litClip.frame = _litOriginalFrame;
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ _litClip.frame = target; } completion:nil];
    }
    _shown = YES;
    if (still) return;
    _dim.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ _dim.alpha = 1; }];
    /* the sheet rises from under the bottom edge and the strip fades in over the message, as the menus of telegram for ios 4 came */
    if (_sheet) {
        CGRect rest = _sheet.frame;
        _sheet.frame = CGRectOffset(rest, 0, self.bounds.size.height - rest.origin.y);
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ _sheet.frame = rest; } completion:nil];
    }
    if (_bar) {
        _bar.alpha = 0;
        _bar.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.18 delay:0.08 options:UIViewAnimationOptionCurveEaseOut animations:^{
            _bar.alpha = 1;
            _bar.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)leaveThen:(void (^)(void))after {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    void (^next)(void) = [after copy];
    [self retain];
    void (^finish)(void) = ^{
        [self removeFromSuperview];
        if (next) next();
        [next release];
        [self release];
    };
    finish = [[finish copy] autorelease];
    if (NoshiReduceMotionEnabled() || !self.window || ![UIView areAnimationsEnabled]) {
        finish();
        return;
    }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        _dim.alpha = 0;
        _bar.alpha = 0;
        if (_lit) _litClip.frame = _litOriginalFrame;
        if (_sheet) _sheet.frame = CGRectOffset(_sheet.frame, 0, self.bounds.size.height - _sheet.frame.origin.y);
    } completion:^(BOOL finished) {
        (void)finished;
        finish();
    }];
}

- (void)dismiss {
    [self leaveThen:^{ if (_dismissHandler) _dismissHandler(); }];
}

- (void)rowTapped:(UIButton *)button {
    NSUInteger tag = (NSUInteger)button.tag;
    void (^handler)(NSUInteger) = [_pickHandler retain];
    [self leaveThen:^{
        if (handler) handler(tag);
        [handler release];
    }];
}

- (void)headerTapped {
    void (^handler)(void) = [_headerHandler retain];
    [self leaveThen:^{ if (handler) handler(); [handler release]; }];
}

- (void)reactorsTapped {
    void (^handler)(void) = [_reactorsHandler retain];
    [self leaveThen:^{ if (handler) handler(); [handler release]; }];
}

- (void)reactionTapped:(UIButton *)button {
    if ((NSUInteger)button.tag >= _reactions.count) return;
    NoshiReaction *reaction = [[_reactions objectAtIndex:(NSUInteger)button.tag] retain];
    void (^handler)(NoshiReaction *) = [_reactionHandler retain];
    [self leaveThen:^{
        if (handler) handler(reaction);
        [handler release];
        [reaction release];
    }];
}

- (void)moreReactionsTapped {
    void (^handler)(void) = [_moreReactionsHandler retain];
    [self leaveThen:^{
        if (handler) handler();
        [handler release];
    }];
}

@end
