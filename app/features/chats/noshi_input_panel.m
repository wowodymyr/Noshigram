#import "noshi_input_panel.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_emoji_store.h"
#import "noshi_symbol.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"

#define PILL_HEIGHT 38.0
#define PILL_MARGIN 8.0
#define SEGMENT_MIN 72.0
#define BACKSPACE_WIDTH 48.0
/* the room the lists leave at the foot, under the pill, so the last row can be scrolled out from under it */
#define FOOT (PILL_HEIGHT + 2 * PILL_MARGIN)

typedef enum { NoshiPageEmoji, NoshiPageGifs, NoshiPageStickers, NoshiPageCustom } NoshiPage;

@interface NoshiInputPanel () <UIGestureRecognizerDelegate> {
    NoshiEmojiPicker *_emoji;
    NoshiGifPicker *_gifs;
    NoshiStickerPicker *_stickers;
    NoshiCustomEmojiPicker *_custom;
    UIView *_pill;
    UIButton *_emojiTab;
    UIButton *_gifTab;
    UIButton *_stickerTab;
    UIButton *_customTab;
    UIView *_marker;
    UIButton *_backspace;
    NSTimer *_repeat;
    NoshiPage _page;
}
@end

@implementation NoshiInputPanel

@synthesize delegate = _delegate;

- (UIButton *)segmentWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = NoshiFontSemibold(15);
    /* a segment squeezed by the delete key keeps its whole word */
    NoshiLabelFitToWidth(button.titleLabel, 11);
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_pill addSubview:button];
    return button;
}

- (void)enableEmojiSearchWithSession:(NoshiSession *)session {
    _emoji.session = session;
}

- (id)initWithMedia:(NoshiMediaCache *)media library:(NoshiStickerLibrary *)library {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = NoshiColorBar();
    _emoji = [[NoshiEmojiPicker alloc] init];
    _emoji.delegate = self;
    [self addSubview:_emoji];
    _stickers = [[NoshiStickerPicker alloc] initWithMedia:media library:library];
    _stickers.delegate = self;
    _stickers.bottomInset = FOOT;
    _stickers.hidden = YES;
    [self addSubview:_stickers];
    _pill = [[UIView alloc] init];
    _pill.backgroundColor = [NoshiColorField() colorWithAlphaComponent:0.96];
    _pill.layer.cornerRadius = PILL_HEIGHT / 2;
    _pill.layer.borderColor = NoshiColorHairline().CGColor;
    _pill.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    [self addSubview:_pill];
    _marker = [[UIView alloc] init];
    _marker.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:0.2];
    _marker.layer.cornerRadius = (PILL_HEIGHT - 8) / 2;
    [_pill addSubview:_marker];
    _emojiTab = [[self segmentWithTitle:NSLocalizedString(@"panel.emoji", nil) action:@selector(showEmoji)] retain];
    _stickerTab = [[self segmentWithTitle:NSLocalizedString(@"panel.stickers", nil) action:@selector(showStickers)] retain];
    _backspace = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_backspace setImage:NoshiSymbolImage(NoshiSymbolBackspace, 24, NoshiColorSecondary()) forState:UIControlStateNormal];
    [_backspace addTarget:self action:@selector(backspaceDown) forControlEvents:UIControlEventTouchDown];
    [_backspace addTarget:self action:@selector(backspaceUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:_backspace];
    for (NSUInteger i = 0; i < 2; ++i) {
        UISwipeGestureRecognizer *swipe = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(pageSwiped:)] autorelease];
        swipe.delegate = self;
        swipe.direction = i ? UISwipeGestureRecognizerDirectionRight : UISwipeGestureRecognizerDirectionLeft;
        [self addGestureRecognizer:swipe];
    }
    [self refreshTabs];
    return self;
}

- (void)dealloc {
    [_repeat invalidate];
    _emoji.delegate = nil;
    _stickers.delegate = nil;
    _gifs.delegate = nil;
    [_emoji release];
    [_stickers release];
    [_gifs release];
    _custom.delegate = nil;
    [_custom release];
    [_pill release];
    [_marker release];
    [_customTab release];
    [_gifTab release];
    [_emojiTab release];
    [_stickerTab release];
    [_backspace release];
    [super dealloc];
}

/* the tabs that exist, left to right */
- (NSArray *)pages {
    NSMutableArray *pages = [NSMutableArray arrayWithObject:[NSNumber numberWithInt:NoshiPageEmoji]];
    if (_gifs) [pages addObject:[NSNumber numberWithInt:NoshiPageGifs]];
    [pages addObject:[NSNumber numberWithInt:NoshiPageStickers]];
    if (_custom) [pages addObject:[NSNumber numberWithInt:NoshiPageCustom]];
    return pages;
}

- (UIButton *)tabOfPage:(NoshiPage)page {
    switch (page) {
    case NoshiPageEmoji: return _emojiTab;
    case NoshiPageGifs: return _gifTab;
    case NoshiPageStickers: return _stickerTab;
    case NoshiPageCustom: return _customTab;
    }
    return nil;
}

- (void)refreshTabs {
    for (NSNumber *page in [self pages]) {
        UIButton *tab = [self tabOfPage:(NoshiPage)page.intValue];
        BOOL current = (NoshiPage)page.intValue == _page;
        [tab setTitleColor:current ? NoshiColorTitle() : NoshiColorSecondary() forState:UIControlStateNormal];
        if (page.intValue == NoshiPageCustom) [tab setImage:NoshiSymbolImage(NoshiSymbolStar, 22, current ? NoshiColorAccent() : NoshiColorSecondary()) forState:UIControlStateNormal];
    }
    _backspace.hidden = _page == NoshiPageStickers || _page == NoshiPageGifs;
    [self setNeedsLayout];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scroll = (UIScrollView *)view;
            if (scroll.contentSize.width > scroll.bounds.size.width + 1) return NO;
        }
    }
    return YES;
}

- (void)pageSwiped:(UISwipeGestureRecognizer *)swipe {
    NSArray *pages = [self pages];
    NSInteger at = (NSInteger)[pages indexOfObject:[NSNumber numberWithInt:_page]];
    NSInteger next = at + (swipe.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1);
    if (next < 0 || next >= (NSInteger)pages.count) return;
    [self showPage:(NoshiPage)[[pages objectAtIndex:(NSUInteger)next] intValue]];
}

- (UIView *)viewOfPage:(NoshiPage)page {
    switch (page) {
    case NoshiPageEmoji: return _emoji;
    case NoshiPageGifs: return _gifs;
    case NoshiPageStickers: return _stickers;
    case NoshiPageCustom: return _custom;
    }
    return nil;
}

/* a page comes in from the side its tab lies on */
- (void)showPage:(NoshiPage)page {
    if (page == _page && ![self viewOfPage:page].hidden) return;
    NSArray *pages = [self pages];
    NSInteger from = (NSInteger)[pages indexOfObject:[NSNumber numberWithInt:_page]], to = (NSInteger)[pages indexOfObject:[NSNumber numberWithInt:page]];
    for (NSNumber *other in pages) [self viewOfPage:(NoshiPage)other.intValue].hidden = YES;
    _page = page;
    UIView *view = [self viewOfPage:page];
    view.hidden = NO;
    if (page == NoshiPageStickers) [_stickers prepare];
    else if (page == NoshiPageGifs) [_gifs prepare];
    else if (page == NoshiPageCustom) [_custom prepare];
    [self refreshTabs];
    view.transform = CGAffineTransformMakeTranslation(to >= from ? 16 : -16, 0);
    view.alpha = 0;
    NoshiAnimateView(view, CGAffineTransformIdentity, 1, NOSHI_MOTION_ENTER, nil);
}

- (void)showEmoji { [self showPage:NoshiPageEmoji]; }
- (void)showGifs { [self showPage:NoshiPageGifs]; }
- (void)showStickers { [self showPage:NoshiPageStickers]; }
- (void)showCustom { [self showPage:NoshiPageCustom]; }

- (void)enableCustomEmojiWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media {
    if (_custom) return;
    _custom = [[NoshiCustomEmojiPicker alloc] initWithSession:session media:media];
    _custom.delegate = self;
    _custom.hidden = YES;
    [self insertSubview:_custom aboveSubview:_stickers];
    _customTab = [[self segmentWithTitle:nil action:@selector(showCustom)] retain];
    [self refreshTabs];
    [self setNeedsLayout];
}

- (void)enableGifsWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media library:(NoshiStickerLibrary *)library dialog:(NoshiDialog *)dialog {
    if (_gifs) return;
    _gifs = [[NoshiGifPicker alloc] initWithSession:session media:media library:library];
    _gifs.delegate = self;
    _gifs.dialog = dialog;
    _gifs.bottomInset = FOOT;
    _gifs.hidden = YES;
    [self insertSubview:_gifs aboveSubview:_emoji];
    _gifTab = [[self segmentWithTitle:@"GIF" action:@selector(showGifs)] retain];
    [self refreshTabs];
    [self setNeedsLayout];
}

- (void)customEmojiPicker:(NoshiCustomEmojiPicker *)picker didPickEmoji:(NoshiCustomEmojiDocument *)emoji {
    (void)picker;
    [_delegate inputPanel:self didPickCustomEmoji:emoji];
}

- (void)gifPicker:(NoshiGifPicker *)picker didPickGif:(NoshiMedia *)gif {
    (void)picker;
    [_delegate inputPanel:self didPickGif:gif];
}

- (void)gifPicker:(NoshiGifPicker *)picker didPickInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId {
    (void)picker;
    [_delegate inputPanel:self didPickInlineResult:result queryId:queryId];
}

- (void)stickerPickerDidTapCreate:(NoshiStickerPicker *)picker {
    (void)picker;
    [_delegate inputPanelDidTapCreateSticker:self];
}

/* a held delete key repeats, as the system keyboard's does */
- (void)backspaceDown {
    [_delegate inputPanelDidTapBackspace:self];
    [_repeat invalidate];
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.09 target:self selector:@selector(repeatBackspace) userInfo:nil repeats:YES];
    _repeat.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.4];
}

- (void)repeatBackspace {
    [_delegate inputPanelDidTapBackspace:self];
}

- (void)backspaceUp {
    [_repeat invalidate];
    _repeat = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* the emoji grids stop above the pill; the lists of stickers and animations run to the foot and scroll under it */
    CGFloat contentHeight = size.height - FOOT;
    _emoji.frame = CGRectMake(0, 0, size.width, contentHeight);
    _custom.frame = CGRectMake(0, 0, size.width, contentHeight);
    _stickers.frame = CGRectMake(0, 0, size.width, size.height);
    _gifs.frame = CGRectMake(0, 0, size.width, size.height);
    NSArray *pages = [self pages];
    CGFloat width = 0;
    NSMutableArray *widths = [NSMutableArray array];
    for (NSNumber *page in pages) {
        CGFloat segment = page.intValue == NoshiPageCustom ? 48 : MAX(SEGMENT_MIN, ceil([[[self tabOfPage:(NoshiPage)page.intValue] titleForState:UIControlStateNormal] sizeWithFont:NoshiFontSemibold(15)].width) + 28);
        [widths addObject:[NSNumber numberWithDouble:segment]];
        width += segment;
    }
    width += 8;
    /* the delete key stands at the right edge, so a pill that centering would push under it moves left of it, and one that is still too wide gives up width evenly */
    CGFloat limit = size.width - BACKSPACE_WIDTH - 6 - 8;
    if (width > limit - 8) {
        CGFloat factor = MAX(0.5, (limit - 8 - 8) / (width - 8));
        width = 8;
        for (NSUInteger i = 0; i < widths.count; ++i) {
            CGFloat shrunk = floor([[widths objectAtIndex:i] doubleValue] * factor);
            [widths replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:shrunk]];
            width += shrunk;
        }
    }
    CGFloat x = MAX(8, MIN((size.width - width) / 2, limit - width));
    _pill.frame = CGRectMake(x, size.height - PILL_MARGIN - PILL_HEIGHT, width, PILL_HEIGHT);
    CGFloat at = 4;
    for (NSUInteger i = 0; i < pages.count; ++i) {
        NoshiPage page = (NoshiPage)[[pages objectAtIndex:i] intValue];
        CGFloat segment = [[widths objectAtIndex:i] doubleValue];
        UIButton *tab = [self tabOfPage:page];
        tab.frame = CGRectMake(at, 0, segment, PILL_HEIGHT);
        if (page == _page) _marker.frame = CGRectMake(at, 4, segment, PILL_HEIGHT - 8);
        at += segment;
    }
    _backspace.frame = CGRectMake(size.width - BACKSPACE_WIDTH - 6, size.height - PILL_MARGIN - PILL_HEIGHT, BACKSPACE_WIDTH, PILL_HEIGHT);
}

- (void)emojiPicker:(NoshiEmojiPicker *)picker didPickEntry:(size_t)entry {
    (void)picker;
    [_delegate inputPanel:self didPickEmoji:NoshiEmojiString(entry)];
}

- (void)emojiPickerDidCloseSearch:(NoshiEmojiPicker *)picker {
    (void)picker;
    [_delegate inputPanelDidCloseEmojiSearch:self];
}

- (void)stickerPicker:(NoshiStickerPicker *)picker didPickSticker:(NoshiSticker *)sticker {
    (void)picker;
    [_delegate inputPanel:self didPickSticker:sticker];
}

@end
