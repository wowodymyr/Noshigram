#import "noshi_name_color_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_emoji_label.h"
#import "noshi_gift_screen.h"
#import "noshi_peer_colors.h"
#import "noshi_person.h"
#import "noshi_session_namecolor.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define SWATCH 44.0
#define SWATCH_GAP 14.0
#define GRID_PAD 18.0

/* the preview: a bubble with a quoted reply in the chosen color, over the colors of the chat */
@interface NoshiNameColorPreview : UIView {
    UIView *_bubble;
    UIView *_quote;
    UIView *_bar;
    NoshiEmojiLabel *_name;
    NoshiEmojiLabel *_text;
}
- (void)setName:(NSString *)name color:(UIColor *)color;
@end

@implementation NoshiNameColorPreview

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = NoshiColorChatBackground();
    self.layer.cornerRadius = 22;
    self.layer.masksToBounds = YES;
    /* clipped once, and kept while the page scrolls */
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.accessibilityElementsHidden = YES;
    _bubble = [[UIView alloc] init];
    _bubble.backgroundColor = NoshiColorBubbleIn();
    _bubble.layer.cornerRadius = 17;
    [self addSubview:_bubble];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.font = NoshiFontSemibold(15);
    [_bubble addSubview:_name];
    _quote = [[UIView alloc] init];
    _quote.layer.cornerRadius = 6;
    [_bubble addSubview:_quote];
    _bar = [[UIView alloc] init];
    [_quote addSubview:_bar];
    _text = [[NoshiEmojiLabel alloc] init];
    _text.font = NoshiFontRegular(15);
    _text.numberOfLines = 2;
    _text.textColor = NoshiColorBubbleText(NO);
    _text.text = NSLocalizedString(@"namecolor.preview", nil);
    [_quote addSubview:_text];
    return self;
}

- (void)dealloc {
    [_bubble release];
    [_quote release];
    [_bar release];
    [_name release];
    [_text release];
    [super dealloc];
}

- (void)setName:(NSString *)name color:(UIColor *)color {
    _name.text = name;
    _name.textColor = color;
    _bar.backgroundColor = color;
    _quote.backgroundColor = [color colorWithAlphaComponent:0.14];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat bubbleWidth = MIN(width - 32, 260), bubbleHeight = 112;
    _bubble.frame = CGRectMake(16, floor((height - bubbleHeight) / 2), bubbleWidth, bubbleHeight);
    _name.frame = CGRectMake(14, 10, bubbleWidth - 28, 20);
    _quote.frame = CGRectMake(14, 36, bubbleWidth - 28, 60);
    _bar.frame = CGRectMake(0, 0, 3, 60);
    _text.frame = CGRectMake(12, 8, bubbleWidth - 28 - 20, 44);
}

@end

/* the colors as circles in rows, the chosen one ringed and ticked, a locked one with a padlock */
@interface NoshiNameColorGrid : UIView {
    NSArray *_items;
    NSMutableArray *_swatches;
    NSInteger _chosenId;
    void (^_chooseHandler)(NSDictionary *item);
}
@property (nonatomic, copy) void (^chooseHandler)(NSDictionary *item);
/* each item is a dictionary with id (NSNumber), color (UIColor) and locked (NSNumber) */
- (void)setItems:(NSArray *)items chosenId:(NSInteger)chosenId;
+ (CGFloat)heightForCount:(NSUInteger)count width:(CGFloat)width;
@end

@implementation NoshiNameColorGrid

@synthesize chooseHandler = _chooseHandler;

static NSUInteger NoshiSwatchColumns(CGFloat width) {
    return MAX(4, (NSUInteger)floor((width - 2 * GRID_PAD + SWATCH_GAP) / (SWATCH + SWATCH_GAP)));
}

+ (CGFloat)heightForCount:(NSUInteger)count width:(CGFloat)width {
    NSUInteger columns = NoshiSwatchColumns(width), rows = MAX(1, (count + columns - 1) / columns);
    return 2 * GRID_PAD + (CGFloat)rows * SWATCH + (CGFloat)(rows - 1) * SWATCH_GAP;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = NoshiColorCard();
    self.layer.cornerRadius = 22;
    self.layer.masksToBounds = YES;
    /* clipped once, and kept while the page scrolls */
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    _swatches = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_items release];
    [_swatches release];
    [_chooseHandler release];
    [super dealloc];
}

- (void)setItems:(NSArray *)items chosenId:(NSInteger)chosenId {
    [_items release];
    _items = [items retain];
    _chosenId = chosenId;
    for (UIView *old in _swatches) [old removeFromSuperview];
    [_swatches removeAllObjects];
    for (NSUInteger i = 0; i < items.count; ++i) {
        NSDictionary *item = [items objectAtIndex:i];
        UIControl *swatch = [[[UIControl alloc] init] autorelease];
        swatch.tag = (NSInteger)i;
        swatch.backgroundColor = [item objectForKey:@"color"];
        swatch.layer.cornerRadius = SWATCH / 2;
        BOOL chosen = [[item objectForKey:@"id"] integerValue] == chosenId;
        BOOL locked = [[item objectForKey:@"locked"] boolValue];
        if (chosen) {
            swatch.layer.borderWidth = 3;
            swatch.layer.borderColor = NoshiColorTitle().CGColor;
        }
        if (chosen || locked) {
            UIImageView *mark = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(chosen ? NoshiSymbolCheck : NoshiSymbolLock, 22, [UIColor whiteColor])] autorelease];
            mark.contentMode = UIViewContentModeCenter;
            mark.frame = CGRectMake(0, 0, SWATCH, SWATCH);
            mark.userInteractionEnabled = NO;
            [swatch addSubview:mark];
        }
        [swatch addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        swatch.accessibilityLabel = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
        swatch.accessibilityTraits = chosen ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
        [self addSubview:swatch];
        [_swatches addObject:swatch];
    }
    [self setNeedsLayout];
}

- (void)tapped:(UIControl *)swatch {
    if ((NSUInteger)swatch.tag < _items.count && _chooseHandler) _chooseHandler([_items objectAtIndex:(NSUInteger)swatch.tag]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger columns = NoshiSwatchColumns(self.bounds.size.width);
    CGFloat used = (CGFloat)columns * SWATCH + (CGFloat)(columns - 1) * SWATCH_GAP;
    CGFloat left = floor((self.bounds.size.width - used) / 2);
    for (UIControl *swatch in _swatches) {
        NSUInteger i = (NSUInteger)swatch.tag;
        swatch.frame = CGRectMake(left + (CGFloat)(i % columns) * (SWATCH + SWATCH_GAP), GRID_PAD + (CGFloat)(i / columns) * (SWATCH + SWATCH_GAP), SWATCH, SWATCH);
    }
}

@end

@interface NoshiNameColorController () {
    NoshiSession *_session;
    NoshiPerson *_person;
    NoshiWeakReference *_weak;
    NoshiNameColorPreview *_preview;
    NoshiNameColorGrid *_grid;
    NSInteger _colorId;
    BOOL _busy;
    void (^_changedHandler)(NSInteger colorId);
}
@end

@implementation NoshiNameColorController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(NoshiSession *)session person:(NoshiPerson *)person {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _person = [person retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _colorId = person.nameColor >= 0 ? person.nameColor : NoshiDefaultNameColorId(person.userId);
    self.pageTitle = NSLocalizedString(@"chatset.namecolor", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_person release];
    [_preview release];
    [_grid release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _preview = [[NoshiNameColorPreview alloc] init];
    _grid = [[NoshiNameColorGrid alloc] init];
    NoshiWeakReference *weak = _weak;
    _grid.chooseHandler = ^(NSDictionary *item) { [(NoshiNameColorController *)weak.target choose:item]; };
    [self rebuild];
    /* the list of the server may have changed since it was kept */
    [_session loadNameColors:^(NSArray *colors, NSString *errorName) {
        NoshiNameColorController *me = weak.target;
        if (!me) return;
        if (errorName) NSLog(@"noshigram: the name colors did not load: %@", errorName);
        [me rebuild];
    }];
}

/* the colors on offer: the seven built in, then the ones of the server that are in the list (a hidden one only while it is in use) */
- (NSArray *)items {
    BOOL dark = NoshiThemeIsDark();
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < NoshiBuiltInNameColorCount(); ++i) {
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:i], @"id", NoshiNameColor((NSInteger)i, 0, dark), @"color",
                          [NSNumber numberWithBool:NO], @"locked", nil]];
    }
    for (NSDictionary *option in NoshiServerNameColors()) {
        NSInteger colorId = [[option objectForKey:@"id"] integerValue];
        if (colorId < (NSInteger)NoshiBuiltInNameColorCount()) continue;
        if ([[option objectForKey:@"hidden"] boolValue] && colorId != _colorId) continue;
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:colorId], @"id", NoshiNameColor(colorId, 0, dark), @"color",
                          [NSNumber numberWithBool:!_person.premium], @"locked", nil]];
    }
    return items;
}

- (void)rebuild {
    NSArray *items = [self items];
    [_grid setItems:items chosenId:_colorId];
    [_preview setName:_person.name.length ? _person.name : @"" color:NoshiNameColor(_colorId, _person.userId, NoshiThemeIsDark())];
    NoshiNameColorPreview *preview = _preview;
    NoshiNameColorGrid *grid = _grid;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
        [NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return 164; }]]]];
    NSUInteger count = items.count;
    NoshiSettingsRow *colors = [NoshiSettingsRow viewRowWithView:grid height:^CGFloat(CGFloat width) { return [NoshiNameColorGrid heightForCount:count width:width]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.namecolor.header", nil) footer:NSLocalizedString(@"chatset.namecolor.info", nil)
                                                              rows:[NSArray arrayWithObject:colors]]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)choose:(NSDictionary *)item {
    NSInteger colorId = [[item objectForKey:@"id"] integerValue];
    if (colorId == _colorId || _busy) return;
    if ([[item objectForKey:@"locked"] boolValue]) {
        NoshiGiftAlert(nil, NSLocalizedString(@"chatset.namecolor.premium", nil));
        return;
    }
    _busy = YES;
    NSInteger before = _colorId;
    _colorId = colorId;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session setNameColorId:colorId completion:^(NSString *errorName) {
        NoshiNameColorController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName && ![errorName isEqualToString:@"NOT_MODIFIED"]) {
            NSLog(@"noshigram: setting the name color failed: %@", errorName);
            me->_colorId = before;
            NoshiGiftAlert(nil, [errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] ? NSLocalizedString(@"chatset.namecolor.premium", nil) : NoshiGiftErrorText(errorName));
            [me rebuild];
            return;
        }
        if (me->_changedHandler) me->_changedHandler(colorId);
    }];
}

@end
