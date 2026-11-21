#import "noshi_gift_card.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_gift_backdrop_view.h"
#import "noshi_lite_mode.h"
#import "noshi_lottie_view.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define CARD_RADIUS 14.0
#define STICKER_SIDE 110.0
#define BUTTON_HEIGHT 30.0
#define ROW_GAP 6.0

static UIColor *NoshiGiftCardInk(NoshiStarGift *gift) {
    return gift.unique && gift.hasBackdropColors ? NoshiGiftRgb(gift.backdropText) : [UIColor colorWithWhite:1 alpha:0.6];
}

static NSString *NoshiGiftNumberRibbon(int32_t number) {
    return number > 0 ? [NSString stringWithFormat:@"#%d", (int)number] : nil;
}

@implementation NoshiGiftCardLayout

@synthesize gift = _gift;
@synthesize size = _size;
@synthesize stickerFrame = _stickerFrame;
@synthesize buttonFrame = _buttonFrame;
@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize note = _note;
@synthesize button = _button;
@synthesize titleOrigin = _titleOrigin;
@synthesize subtitleOrigin = _subtitleOrigin;
@synthesize noteOrigin = _noteOrigin;
@synthesize buttonTextOrigin = _buttonTextOrigin;
@synthesize rowNames = _rowNames;
@synthesize rowValues = _rowValues;
@synthesize rowNameOrigins = _rowNameOrigins;
@synthesize rowValueOrigins = _rowValueOrigins;

- (void)dealloc {
    [_gift release];
    [_title release];
    [_subtitle release];
    [_note release];
    [_button release];
    [_rowNames release];
    [_rowValues release];
    [_rowNameOrigins release];
    [_rowValueOrigins release];
    [super dealloc];
}

+ (NoshiGiftCardLayout *)layoutForGift:(NoshiStarGift *)gift title:(NSString *)title subtitle:(NSString *)subtitle note:(NSString *)note
                                    width:(CGFloat)width {
    NoshiGiftCardLayout *card = [[[NoshiGiftCardLayout alloc] init] autorelease];
    card->_gift = [gift retain];
    UIColor *white = [UIColor whiteColor], *ink = NoshiGiftCardInk(gift);
    CGFloat inner = width - 24;
    CGFloat y = 10;
    card->_stickerFrame = CGRectMake(floor((width - STICKER_SIDE) / 2), y, STICKER_SIDE, STICKER_SIDE);
    y += STICKER_SIDE + 9;
    card->_title = [[NoshiTextLayout layoutForName:title font:NoshiFontBold(14) color:white width:inner] retain];
    card->_titleOrigin = CGPointMake(floor((width - card->_title.size.width) / 2), y);
    y += ceil(card->_title.size.height) + 3;
    card->_subtitle = [[NoshiTextLayout layoutForName:subtitle font:NoshiFontRegular(12) color:ink width:inner] retain];
    card->_subtitleOrigin = CGPointMake(floor((width - card->_subtitle.size.width) / 2), y);
    y += ceil(card->_subtitle.size.height) + 11;
    if (note.length) {
        y += 4;
        card->_note = [[NoshiTextLayout layoutForText:note entities:nil font:NoshiFontRegular(13) color:white linkColor:white width:inner
                                                maxLines:4 flush:0.5] retain];
        card->_noteOrigin = CGPointMake(floor((width - inner) / 2), y);
        y += ceil(card->_note.size.height) + 3;
    } else if (gift.unique && gift.model.length) {
        NSMutableArray *names = [NSMutableArray array], *values = [NSMutableArray array];
        NSString *keys[3] = {@"gifts.row.model", @"gifts.row.backdrop", @"gifts.row.pattern"};
        NSString *texts[3] = {gift.model, gift.backdrop, gift.pattern};
        CGFloat nameWidth = 0, valueWidth = 0;
        for (int i = 0; i < 3; ++i) {
            if (!texts[i].length) continue;
            [names addObject:[NoshiTextLayout layoutForName:NSLocalizedString(keys[i], nil) font:NoshiFontRegular(12) color:ink width:inner * 0.5]];
            [values addObject:[NoshiTextLayout layoutForName:texts[i] font:NoshiFontBold(12) color:white width:inner * 0.5]];
            nameWidth = MAX(nameWidth, [[names lastObject] size].width);
            valueWidth = MAX(valueWidth, [[values lastObject] size].width);
        }
        NSMutableArray *nameOrigins = [NSMutableArray array], *valueOrigins = [NSMutableArray array];
        CGFloat left = width / 2 - (nameWidth + 9 + valueWidth) / 2;
        for (NSUInteger i = 0; i < names.count; ++i) {
            NoshiTextLayout *name = [names objectAtIndex:i], *value = [values objectAtIndex:i];
            [nameOrigins addObject:[NSValue valueWithCGPoint:CGPointMake(floor(left + nameWidth - name.size.width), y)]];
            [valueOrigins addObject:[NSValue valueWithCGPoint:CGPointMake(floor(left + nameWidth + 9), y)]];
            y += ceil(MAX(name.size.height, value.size.height)) + (i + 1 < names.count ? ROW_GAP : 0);
        }
        card->_rowNames = [names retain];
        card->_rowValues = [values retain];
        card->_rowNameOrigins = [nameOrigins retain];
        card->_rowValueOrigins = [valueOrigins retain];
    }
    y += 11.66;
    card->_button = [[NoshiTextLayout layoutForName:NSLocalizedString(@"gifts.card.view", nil) font:NoshiFontBold(14) color:white width:inner - 30] retain];
    CGFloat buttonWidth = ceil(card->_button.size.width) + 30;
    card->_buttonFrame = CGRectMake(floor((width - buttonWidth) / 2), y, buttonWidth, BUTTON_HEIGHT);
    card->_buttonTextOrigin = CGPointMake(card->_buttonFrame.origin.x + 15, y + (BUTTON_HEIGHT - ceil(card->_button.size.height)) / 2);
    y += BUTTON_HEIGHT + 11;
    card->_size = CGSizeMake(width, y);
    return card;
}

@end

/* the words and the button, above the animation */
@interface NoshiGiftCardTextView : UIView {
    NoshiGiftCardLayout *_card;
    CAEmitterLayer *_sparkles;
}
@property (nonatomic, retain) NoshiGiftCardLayout *card;
- (void)setSparkling:(BOOL)sparkling;
@end

@implementation NoshiGiftCardTextView

@synthesize card = _card;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [_card release];
    [_sparkles release];
    [super dealloc];
}

/* small blurred points stay within the gift button, as in the original client */
static UIImage *NoshiGiftParticleImage(void) {
    static UIImage *image;
    if (image) return image;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(6, 6), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetShadowWithColor(context, CGSizeZero, 1.5, [UIColor whiteColor].CGColor);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(2, 2, 2, 2));
    image = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return image;
}

- (void)placeSparkles {
    if (!_sparkles || !_card) return;
    _sparkles.frame = _card.buttonFrame;
    _sparkles.cornerRadius = _card.buttonFrame.size.height / 2;
    _sparkles.masksToBounds = YES;
    _sparkles.emitterPosition = CGPointMake(CGRectGetMidX(_sparkles.bounds), CGRectGetMidY(_sparkles.bounds));
    _sparkles.emitterSize = _sparkles.bounds.size;
}

- (void)setCard:(NoshiGiftCardLayout *)card {
    if (card == _card) return;
    [_card release];
    _card = [card retain];
    [self placeSparkles];
    [self setNeedsDisplay];
}

- (void)setSparkling:(BOOL)sparkling {
    if (sparkling && !_sparkles && _card) {
        CAEmitterCell *star = [CAEmitterCell emitterCell];
        star.contents = (id)NoshiGiftParticleImage().CGImage;
        star.birthRate = 7;
        star.lifetime = 1.1;
        star.lifetimeRange = 0.35;
        star.velocity = 0;
        star.velocityRange = 0;
        star.emissionRange = (CGFloat)(2 * M_PI);
        star.scale = 0.5;
        star.scaleRange = 0.25;
        star.alphaSpeed = -0.8;
        star.color = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
        _sparkles = [[CAEmitterLayer alloc] init];
        _sparkles.emitterShape = kCAEmitterLayerRectangle;
        _sparkles.emitterCells = [NSArray arrayWithObject:star];
        [self.layer addSublayer:_sparkles];
        [self placeSparkles];
    }
    _sparkles.birthRate = sparkling ? 1 : 0;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    NoshiGiftCardLayout *card = _card;
    if (!card) return;
    [card.title drawAtPoint:card.titleOrigin];
    [card.subtitle drawAtPoint:card.subtitleOrigin];
    if (card.note) [card.note drawAtPoint:card.noteOrigin];
    for (NSUInteger i = 0; i < card.rowNames.count; ++i) {
        [[card.rowNames objectAtIndex:i] drawAtPoint:[[card.rowNameOrigins objectAtIndex:i] CGPointValue]];
        [[card.rowValues objectAtIndex:i] drawAtPoint:[[card.rowValueOrigins objectAtIndex:i] CGPointValue]];
    }
    CGRect button = card.buttonFrame;
    [[UIColor colorWithWhite:0 alpha:0.13] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:button cornerRadius:button.size.height / 2] fill];
    [card.button drawAtPoint:card.buttonTextOrigin];
}

@end

@interface NoshiGiftCardView () {
    NoshiGiftCardLayout *_layout;
    NoshiGiftBackdropView *_backdrop;
    NoshiGiftRibbonView *_ribbonView;
    UIImageView *_poster;
    NoshiLottieView *_lottie;
    NoshiGiftCardTextView *_text;
    NSUInteger _token;
    BOOL _active;
    BOOL _played;
}
@end

@implementation NoshiGiftCardView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.layer.cornerRadius = CARD_RADIUS;
    self.layer.masksToBounds = YES;
    _backdrop = [[NoshiGiftBackdropView alloc] init];
    [self addSubview:_backdrop];
    _poster = [[UIImageView alloc] init];
    _poster.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_poster];
    _ribbonView = [[NoshiGiftRibbonView alloc] init];
    _ribbonView.hidden = YES;
    [self addSubview:_ribbonView];
    _text = [[NoshiGiftCardTextView alloc] init];
    [self addSubview:_text];
    return self;
}

- (void)dealloc {
    [self discard];
    [_backdrop release];
    [_ribbonView release];
    [_poster release];
    [_text release];
    [super dealloc];
}

- (BOOL)animationAllowed {
    return !NoshiReduceMotionEnabled() && NoshiLiteEnabled(NOSHI_LITE_STICKERS_CHAT);
}

- (void)discard {
    ++_token;
    [_lottie removeFromSuperview];
    [_lottie setPlaying:NO];
    [_lottie release];
    _lottie = nil;
    _poster.image = nil;
    _poster.hidden = NO;
    [_layout release];
    _layout = nil;
    _played = NO;
    [_text setSparkling:NO];
}

- (void)configureWithLayout:(NoshiGiftCardLayout *)layout media:(NoshiMediaCache *)media {
    if (layout == _layout) return;
    [self discard];
    _layout = [layout retain];
    NoshiStarGift *gift = layout.gift;
    NSUInteger token = _token;
    self.bounds = CGRectMake(0, 0, layout.size.width, layout.size.height);
    CGRect all = self.bounds;
    BOOL themed = gift.unique && gift.hasBackdropColors;
    self.backgroundColor = themed ? NoshiGiftRgb(gift.backdropEdge) : NoshiColorBubbleCapsule();
    _backdrop.frame = all;
    _backdrop.hidden = !themed;
    _backdrop.symbol = nil;
    _ribbonView.frame = all;
    _ribbonView.edgeColor = gift.backdropEdge;
    _ribbonView.text = themed ? NoshiGiftNumberRibbon(gift.number) : nil;
    _ribbonView.hidden = !themed || gift.number <= 0;
    if (themed) {
        _backdrop.centerColor = gift.backdropCenter;
        _backdrop.edgeColor = gift.backdropEdge;
        _backdrop.patternColor = gift.backdropPattern;
        _backdrop.focus = CGPointMake(0.5, CGRectGetMidY(layout.stickerFrame) / all.size.height);
        if (gift.patternSticker) {
            NoshiGiftLoadPatternSymbol(media, gift.patternSticker, gift.backdropPattern, ^(UIImage *symbol) {
                if (token == _token) _backdrop.symbol = symbol;
            });
        }
    }
    _poster.frame = layout.stickerFrame;
    _text.frame = all;
    _text.card = layout;
    [self loadAnimationOf:gift.sticker media:media token:token];
    [_text setSparkling:_active && [self animationAllowed]];
}

- (void)loadAnimationOf:(NoshiMedia *)sticker media:(NoshiMediaCache *)media token:(NSUInteger)token {
    if (!sticker || !sticker.file) return;
    CGFloat pixels = STICKER_SIDE * NoshiScreenScale();
    NoshiRemoteFile *preview = sticker.previewFile;
    if (preview) {
        UIImage *ready = [media cachedImageForFile:preview maxSide:pixels];
        if (ready) _poster.image = ready;
        else [media loadImageForFile:preview maxSide:pixels completion:^(UIImage *image) {
            if (token == _token && image && !_lottie) _poster.image = image;
        }];
    }
    NoshiRemoteFile *file = sticker.file;
    [media loadDataForFile:file completion:^(NSData *data) {
        if (token != _token || !data || _lottie) return;
        _lottie = [[NoshiLottieView alloc] initWithPackedData:data key:file.key];
        _lottie.frame = _layout.stickerFrame;
        _lottie.firstFrameHandler = ^{
            if (token == _token) _poster.hidden = YES;
        };
        [_lottie setLoaded:YES];
        [self insertSubview:_lottie aboveSubview:_poster];
        [self playIfDue];
    }];
}

/* the animation plays once, the first time the card is on screen; scrolling back does not run it again */
- (void)playIfDue {
    if (!_active || _played || !_lottie || ![self animationAllowed]) return;
    _played = YES;
    [_lottie playOnce];
}

- (void)setActive:(BOOL)active {
    _active = active;
    [_text setSparkling:active && [self animationAllowed]];
    [self playIfDue];
}

@end
