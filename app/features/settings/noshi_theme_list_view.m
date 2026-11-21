#import "noshi_theme_list_view.h"
#import "noshi_imported_theme.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_theme.h"
#import "noshi_wallpaper.h"
#import "noshi_blur.h"
#import "noshi_symbol.h"
#import "noshi_alert.h"

#define CARD_WIDTH 96.0
#define CARD_HEIGHT 132.0
#define CARD_GAP 12.0
#define CARD_RADIUS 14.0
#define LABEL_HEIGHT 34.0
#define SIDE_PAD 16.0
#define TOP_PAD 14.0
#define RING 3.0
#define THEME_COUNT 2
/* the scrolling area stops this far from the edges of the rounded list, so a card that slides out is cut inside the corner and never shows beside it */
#define EDGE 8.0

@interface NoshiThemeCard : UIControl {
    BOOL _dark;
}
- (id)initWithDark:(BOOL)dark;
@property (nonatomic, readonly) BOOL dark;
@end

@implementation NoshiThemeCard

@synthesize dark = _dark;

static UIView *NoshiThemeBubble(UIView *host, UIColor *color, CGRect frame, CGFloat radius) {
    UIView *bubble = [[[UIView alloc] initWithFrame:frame] autorelease];
    bubble.backgroundColor = color;
    bubble.layer.cornerRadius = radius;
    bubble.userInteractionEnabled = NO;
    [host addSubview:bubble];
    return bubble;
}

- (id)initWithDark:(BOOL)dark {
    self = [super initWithFrame:CGRectMake(0, 0, CARD_WIDTH, CARD_HEIGHT + LABEL_HEIGHT)];
    if (!self) return nil;
    _dark = dark;
    UIView *picture = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, CARD_WIDTH, CARD_HEIGHT)] autorelease];
    picture.layer.cornerRadius = CARD_RADIUS;
    picture.layer.masksToBounds = YES;
    /* the picture of a card never changes, so it is clipped once and moves with the list as a texture */
    picture.layer.shouldRasterize = YES;
    picture.layer.rasterizationScale = [UIScreen mainScreen].scale;
    picture.userInteractionEnabled = NO;
    picture.tag = 1;
    [self addSubview:picture];
    UIImageView *wallpaper = [[[UIImageView alloc] initWithFrame:picture.bounds] autorelease];
    NoshiApplyWallpaperStyle(wallpaper, dark);
    [picture addSubview:wallpaper];
    UIColor *incoming = nil, *outgoing = nil;
    NoshiThemePreviewColors(dark, &incoming, &outgoing, NULL, NULL);
    /* two bubbles of the theme: theirs on the left, ours on the right, and a shorter reply under them */
    NoshiThemeBubble(picture, incoming, CGRectMake(10, 18, 58, 26), 11);
    NoshiThemeBubble(picture, outgoing, CGRectMake(CARD_WIDTH - 10 - 62, 52, 62, 26), 11);
    NoshiThemeBubble(picture, incoming, CGRectMake(10, 86, 44, 22), 10);
    UILabel *name = [[[UILabel alloc] initWithFrame:CGRectMake(-6, CARD_HEIGHT + 4, CARD_WIDTH + 12, LABEL_HEIGHT - 4)] autorelease];
    name.backgroundColor = [UIColor clearColor];
    name.textAlignment = NoshiTextAlignmentCenter;
    name.numberOfLines = 1;
    name.font = NoshiFontMedium(12);
    name.tag = 2;
    name.text = NSLocalizedString(dark ? @"chatset.theme.night.short" : @"chatset.theme.day.short", nil);
    [self addSubview:name];
    self.accessibilityLabel = name.text;
    return self;
}

/* the ring stands outside the picture, so a chosen card is the same size as the others */
- (void)showSelected:(BOOL)selected {
    UIView *picture = [self viewWithTag:1];
    picture.layer.borderWidth = selected ? RING : 0;
    picture.layer.borderColor = NoshiColorAccent().CGColor;
    UILabel *name = (UILabel *)[self viewWithTag:2];
    name.textColor = selected ? NoshiColorAccent() : NoshiColorSecondary();
    self.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.7 : 1;
}

@end

@interface NoshiThemeListView () {
    UIScrollView *_scroll;
    NSMutableArray *_cards;
    void (^_chooseHandler)(BOOL dark);
    CGPoint _tapPoint;
}
@end

@implementation NoshiThemeListView

@synthesize chooseHandler = _chooseHandler;
@synthesize tapPoint = _tapPoint;

+ (CGFloat)height {
    return TOP_PAD + CARD_HEIGHT + LABEL_HEIGHT + TOP_PAD;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = NoshiColorCard();
    /* the list scrolls, and a clip to rounded corners over scrolling content is drawn again at every frame; the cards stop short of the corners instead */
    self.layer.cornerRadius = 22;
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsHorizontalScrollIndicator = NO;
    [self addSubview:_scroll];
    _cards = [[NSMutableArray alloc] init];
    /* the day, then the night */
    for (int i = 0; i < THEME_COUNT; ++i) {
        NoshiThemeCard *card = [[[NoshiThemeCard alloc] initWithDark:i == 1] autorelease];
        [card addTarget:self action:@selector(cardTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:card];
        [_cards addObject:card];
    }
    [self refreshSelection];
    return self;
}

- (void)dealloc {
    [_scroll release];
    [_cards release];
    [_chooseHandler release];
    [super dealloc];
}

- (void)refreshSelection {
    /* while an imported theme is on, neither built-in card is the one in use, and a tap on either brings the colors of the app back */
    BOOL imported = NoshiImportedThemeSelected(NoshiThemeIsDark());
    for (NoshiThemeCard *card in _cards) [card showSelected:!imported && card.dark == NoshiThemeIsDark()];
}

- (void)cardTapped:(NoshiThemeCard *)card {
    if (card.dark == NoshiThemeIsDark() && !NoshiImportedThemeSelected(card.dark)) return;
    _tapPoint = [card.superview convertPoint:card.center toView:nil];
    if (_chooseHandler) _chooseHandler(card.dark);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = CGRectInset(self.bounds, EDGE, 0);
    CGFloat x = SIDE_PAD - EDGE;
    for (NoshiThemeCard *card in _cards) {
        card.frame = CGRectMake(x, TOP_PAD, CARD_WIDTH, CARD_HEIGHT + LABEL_HEIGHT);
        x += CARD_WIDTH + CARD_GAP;
    }
    _scroll.contentSize = CGSizeMake(x - CARD_GAP + SIDE_PAD - EDGE, self.bounds.size.height);
}

@end
