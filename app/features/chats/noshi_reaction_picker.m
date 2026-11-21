#import "noshi_reaction_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_blur.h"
#import "noshi_custom_emoji_picker.h"
#import "noshi_emoji_label.h"
#import "noshi_platform.h"
#import "noshi_reaction_artwork.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define CARD_MAX_WIDTH 344.0
#define CARD_MIN_HEIGHT 260.0
#define CARD_EDGE 12.0
#define ANCHOR_GAP 8.0
#define CELL_TARGET 44.0
#define CELL_MIN_COLUMNS 5
#define SIDE_PAD 6.0
/* the side of the still picture of a reaction */
#define APPEAR_SIDE 31.0

@interface NoshiReactionPicker () <NoshiCustomEmojiPickerDelegate> {
    UIControl *_dim;
    UIView *_card;
    UILabel *_status;
    UIButton *_retry;
    UIScrollView *_scroll;
    NoshiCustomEmojiPicker *_sets;
    NoshiSession *_session;
    NoshiMediaCache *_media;
    BOOL _premium;
    BOOL _customAllowed;
    NSArray *_reactions;
    NSArray *_buttons;
    CGRect _anchorRect;
    BOOL _anchorOutgoing;
    BOOL _opened;
    BOOL _below;
    NoshiWeakReference *_weak;
    BOOL _closing;
}
@end

@implementation NoshiReactionPicker

@synthesize pickHandler = _pickHandler;
@synthesize customPickHandler = _customPickHandler;
@synthesize cancelHandler = _cancelHandler;
@synthesize retryHandler = _retryHandler;
@synthesize anchorRect = _anchorRect;
@synthesize anchorOutgoing = _anchorOutgoing;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.accessibilityViewIsModal = YES;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _dim = [[UIControl alloc] initWithFrame:self.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    [_dim addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = NoshiColorBar();
    _card.layer.cornerRadius = 12;
    _card.layer.shadowColor = [UIColor blackColor].CGColor;
    _card.layer.shadowOpacity = 0.3f;
    _card.layer.shadowRadius = 12;
    _card.layer.shadowOffset = CGSizeMake(0, 4);
    [self addSubview:_card];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = NoshiColorSecondary();
    _status.font = NoshiFontRegular(15);
    _status.numberOfLines = 0;
    _status.textAlignment = NoshiTextAlignmentCenter;
    [_card addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _retry.titleLabel.font = NoshiFontMedium(16);
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_retry];
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.layer.cornerRadius = _card.layer.cornerRadius;
    _scroll.clipsToBounds = YES;
    [_card addSubview:_scroll];
    [self setLoading];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _sets.delegate = nil;
    [_dim release];
    [_card release];
    [_status release];
    [_retry release];
    [_scroll release];
    [_sets release];
    [_session release];
    [_media release];
    [_reactions release];
    [_buttons release];
    [_pickHandler release];
    [_customPickHandler release];
    [_cancelHandler release];
    [_retryHandler release];
    [super dealloc];
}

/* the custom emoji sets share the card with the reactions: they own the strip at the top, whose first tab is the reactions themselves */
- (void)attachSession:(NoshiSession *)session media:(NoshiMediaCache *)media premium:(BOOL)premium {
    [_session release];
    _session = [session retain];
    [_media release];
    _media = [media retain];
    _premium = premium;
    _sets.showsLocks = !premium;
    [self buildSetsIfAllowed];
}

/* a chat that lists its reactions takes only those, so its picker has no emoji panel to pick others from; the server answers REACTION_INVALID for them */
- (void)setCustomAllowed:(BOOL)allowed {
    _customAllowed = allowed;
    if (allowed) {
        [self buildSetsIfAllowed];
        return;
    }
    _sets.delegate = nil;
    [_sets removeFromSuperview];
    [_sets release];
    _sets = nil;
    _scroll.hidden = !_buttons.count;
    [self setNeedsLayout];
}

- (void)buildSetsIfAllowed {
    NoshiSession *session = _session;
    NoshiMediaCache *media = _media;
    BOOL premium = _premium;
    if (_sets || !_customAllowed || !session || !media) return;
    _sets = [[NoshiCustomEmojiPicker alloc] initWithSession:session media:media];
    _sets.delegate = self;
    _sets.leadingSymbol = NoshiSymbolSmiley;
    _sets.leadingLabel = NSLocalizedString(@"chat.reactions", nil);
    _sets.showsLocks = !premium;
    _sets.hasLeading = YES;
    /* the strip goes under the reactions' own content in z order, so the grid of the reactions can lie over the empty body of the picker */
    [_card insertSubview:_sets belowSubview:_scroll];
    /* the load answers after the picker is on screen, so the strip is prepared here and not in didMoveToWindow */
    if (self.window) [_sets prepare];
    [self setNeedsLayout];
}

- (void)customEmojiPickerDidSelectLeading:(NoshiCustomEmojiPicker *)picker {
    (void)picker;
    _scroll.hidden = !_buttons.count;
    _status.hidden = _buttons.count > 0;
}

- (void)customEmojiPickerDidSelectSet:(NoshiCustomEmojiPicker *)picker {
    (void)picker;
    _scroll.hidden = YES;
    _status.hidden = YES;
    _retry.hidden = YES;
}

- (void)customEmojiPicker:(NoshiCustomEmojiPicker *)picker didPickEmoji:(NoshiCustomEmojiDocument *)emoji {
    (void)picker;
    if (_closing || !emoji) return;
    void (^handler)(NoshiCustomEmojiDocument *) = [_customPickHandler copy];
    if (handler) handler(emoji);
    [handler release];
}

- (void)cancel {
    if (_closing) return;
    void (^handler)(void) = [_cancelHandler copy];
    if (handler) handler();
    [handler release];
}

- (void)retry {
    if (_closing) return;
    void (^handler)(void) = [_retryHandler copy];
    if (handler) handler();
    [handler release];
}

- (void)showMessage:(NSString *)text retry:(BOOL)retry {
    _status.text = text;
    _status.hidden = NO;
    _retry.hidden = !retry;
    _scroll.hidden = YES;
    [self setNeedsLayout];
}

- (void)setLoading {
    [self showMessage:NSLocalizedString(@"chat.reaction.loading", nil) retry:NO];
}

- (void)setFailure:(NSString *)error {
    [self showMessage:error retry:YES];
}

/* the card opens from the corner of it that is nearest the message, the way the menu does */
- (CGPoint)cornerAnchor {
    return CGPointMake(_anchorOutgoing ? 1 : 0, _below ? 0 : 1);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || _closing || _opened) return;
    _opened = YES;
    /* the picture of the screen is taken with the picker itself out of it, so the blur holds the chat alone */
    self.hidden = YES;
    UIView *blur = NoshiBlurBackdrop(self.superview, self.bounds);
    self.hidden = NO;
    if (blur) {
        blur.userInteractionEnabled = NO;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_dim insertSubview:blur atIndex:0];
    }
    [_sets prepare];
    [self layoutIfNeeded];
    _dim.alpha = 0;
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
    CGPoint corner = [self cornerAnchor];
    CGRect frame = _card.frame;
    _card.layer.anchorPoint = corner;
    _card.layer.position = CGPointMake(frame.origin.x + frame.size.width * corner.x, frame.origin.y + frame.size.height * corner.y);
    _card.alpha = 0;
    _card.transform = CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale());
    NoshiAnimateView(_card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}

- (void)dismissAnimated:(BOOL)animated {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    if (!animated) {
        [self removeFromSuperview];
        return;
    }
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(_card, CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale()), 0, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}

#pragma mark grid

- (UIButton *)buttonForReaction:(NoshiReaction *)reaction index:(NSUInteger)index {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = (NSInteger)index;
    button.layer.cornerRadius = 12;
    if (reaction.chosen) button.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:0.28];
    button.accessibilityLabel = reaction.displayText;
    button.accessibilityTraits = UIAccessibilityTraitButton | (reaction.chosen ? UIAccessibilityTraitSelected : 0);
    [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(cellDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(cellUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    NoshiEmojiLabel *label = [[[NoshiEmojiLabel alloc] init] autorelease];
    label.text = reaction.displayText;
    label.entities = reaction.displayEntities;
    label.font = NoshiFontRegular(31);
    label.textAlignment = NoshiTextAlignmentCenter;
    label.userInteractionEnabled = NO;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.frame = button.bounds;
    label.tag = NOSHI_REACTION_LABEL_TAG;
    [button addSubview:label];
    /* the big card does not animate: the still picture, the first frame of the select animation that the pop of the pill ends on, stands in the place of the label from the start */
    NoshiReactionArtwork *artwork = reaction.row.kind == NOSHI_REACTION_EMOJI ? [NoshiReactionArtwork artForEmoji:reaction.emoji] : nil;
    if (artwork) [NoshiReactionArtwork attachStillOfArtwork:artwork toButton:button side:APPEAR_SIDE media:_media];
    return button;
}

- (void)cellDown:(UIButton *)button {
    button.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:0.2];
}

- (void)cellUp:(UIButton *)button {
    NoshiReaction *reaction = (NSUInteger)button.tag < _reactions.count ? [_reactions objectAtIndex:(NSUInteger)button.tag] : nil;
    button.backgroundColor = reaction.chosen ? [NoshiColorAccent() colorWithAlphaComponent:0.28] : [UIColor clearColor];
}

- (void)picked:(UIButton *)button {
    if ((NSUInteger)button.tag >= _reactions.count) return;
    /* picking closes the overlay and releases its views before this touch handler returns */
    NoshiReaction *reaction = [[_reactions objectAtIndex:(NSUInteger)button.tag] retain];
    void (^handler)(NoshiReaction *) = [_pickHandler copy];
    if (!_closing && handler) handler(reaction);
    [handler release];
    [reaction release];
}

- (void)setReactions:(NSArray *)reactions {
    for (UIView *button in _buttons) [button removeFromSuperview];
    [_buttons release];
    _buttons = nil;
    [_reactions release];
    _reactions = [reactions copy];
    NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:reactions.count];
    for (NSUInteger i = 0; i < reactions.count; ++i) {
        UIButton *button = [self buttonForReaction:[reactions objectAtIndex:i] index:i];
        [_scroll addSubview:button];
        [buttons addObject:button];
    }
    _buttons = [buttons copy];
    _status.text = NSLocalizedString(@"chat.reaction.disabled", nil);
    _status.hidden = reactions.count > 0;
    _retry.hidden = YES;
    _scroll.hidden = !reactions.count;
    [self setNeedsLayout];
}

/* places the cells in rows of equal squares and returns the height of the grid */
- (CGFloat)layoutGridInWidth:(CGFloat)width {
    NSUInteger columns = MAX((NSUInteger)CELL_MIN_COLUMNS, (NSUInteger)floor(width / CELL_TARGET));
    CGFloat cell = floor(width / (CGFloat)columns);
    CGFloat left = floor((width - cell * (CGFloat)columns) / 2);
    for (NSUInteger i = 0; i < _buttons.count; ++i) {
        UIView *button = [_buttons objectAtIndex:i];
        button.frame = CGRectMake(left + cell * (CGFloat)(i % columns), cell * (CGFloat)(i / columns), cell, cell);
    }
    return cell * (CGFloat)((_buttons.count + columns - 1) / columns);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    UIEdgeInsets insets = NoshiSafeInsets(self);
    CGFloat width = MIN(CARD_MAX_WIDTH, size.width - 2 * CARD_EDGE);
    /* nearly square, as the card of the original client is, and short enough to leave the bars of the screen free */
    CGFloat room = size.height - insets.top - insets.bottom - 2 * CARD_EDGE;
    CGFloat height = MAX(CARD_MIN_HEIGHT, MIN(floor(width * 1.12), room));
    CGFloat x, y;
    BOOL centered = CGRectIsEmpty(_anchorRect);
    if (centered) {
        x = floor((size.width - width) / 2);
        y = floor((size.height - height) / 2);
        _below = YES;
    } else {
        x = _anchorOutgoing ? CGRectGetMaxX(_anchorRect) - width : CGRectGetMinX(_anchorRect);
        y = CGRectGetMaxY(_anchorRect) + ANCHOR_GAP;
        _below = YES;
        if (y + height > size.height - insets.bottom - CARD_EDGE) {
            CGFloat above = CGRectGetMinY(_anchorRect) - ANCHOR_GAP - height;
            if (above >= insets.top + CARD_EDGE) {
                y = above;
                _below = NO;
            } else {
                y = MAX(insets.top + CARD_EDGE, size.height - insets.bottom - CARD_EDGE - height);
            }
        }
    }
    x = MIN(MAX(CARD_EDGE + insets.left, x), size.width - CARD_EDGE - insets.right - width);
    CGAffineTransform held = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(x, y, width, height);
    _card.transform = held;
    CGFloat strip = _sets ? [NoshiCustomEmojiPicker stripHeight] : 0;
    _sets.frame = _card.bounds;
    CGFloat bodyHeight = height - strip;
    CGFloat gridWidth = width - 2 * SIDE_PAD;
    CGFloat gridHeight = _buttons.count ? [self layoutGridInWidth:gridWidth] : 0;
    _scroll.frame = CGRectMake(SIDE_PAD, strip, gridWidth, bodyHeight);
    _scroll.contentSize = CGSizeMake(gridWidth, gridHeight);
    _scroll.bounces = gridHeight > bodyHeight;
    for (UIView *button in _buttons) {
        UIView *still = [button viewWithTag:NOSHI_REACTION_STILL_TAG];
        still.center = CGPointMake(button.bounds.size.width / 2, button.bounds.size.height / 2);
    }
    _status.frame = CGRectMake(16, strip, width - 32, bodyHeight - (_retry.hidden ? 0 : 40));
    _retry.frame = CGRectMake(16, height - 40, width - 32, 40);
}

@end
