#import "noshi_music_pill.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_emoji_label.h"
#import "noshi_music_player.h"
#import "noshi_music_style.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define CARD_HEIGHT 60.0
#define COVER_INSET 15.0
#define COVER_SIDE 44.0
#define KEY_SIDE 30.0
#define SLOT 34.0
/* the part of the card, from its right edge, that the pattern may reach */
#define PATTERN_REACH 0.42

/* the emoji of the profile as a few marks that run onto the right end of the card, each fainter toward the left; the marks stand at fixed places so a
   card looks the same every time it is drawn */
@interface NoshiMusicPatternView : UIView {
    UIImage *_image;
    UIColor *_color;
}
- (void)setImage:(UIImage *)image color:(UIColor *)color;
@end

@implementation NoshiMusicPatternView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    return self;
}

- (void)dealloc {
    [_image release];
    [_color release];
    [super dealloc];
}

- (void)setImage:(UIImage *)image color:(UIColor *)color {
    [_image release];
    _image = [image retain];
    [_color release];
    _color = [color retain];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_image.CGImage || !_color) return;
    /* x and y as fractions of the view, then the size as a fraction of its height, then the alpha */
    static const CGFloat marks[][4] = {
        {0.80f, 0.20f, 0.30f, 0.30f}, {0.55f, 0.72f, 0.24f, 0.22f}, {0.93f, 0.62f, 0.34f, 0.34f},
        {0.30f, 0.30f, 0.20f, 0.14f}, {0.66f, 0.40f, 0.18f, 0.16f}, {0.12f, 0.78f, 0.17f, 0.10f}
    };
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGSize size = self.bounds.size;
    for (size_t i = 0; i < sizeof(marks) / sizeof(marks[0]); ++i) {
        CGFloat side = size.height * marks[i][2];
        CGRect box = CGRectMake(size.width * marks[i][0] - side / 2, size.height * marks[i][1] - side / 2, side, side);
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, box.origin.x, box.origin.y + side);
        CGContextScaleCTM(context, 1, -1);
        CGContextClipToMask(context, CGRectMake(0, 0, side, side), _image.CGImage);
        CGContextSetFillColorWithColor(context, [_color colorWithAlphaComponent:marks[i][3]].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, side, side));
        CGContextRestoreGState(context);
    }
}

@end

@interface NoshiMusicPill () {
    NoshiMedia *_savedTrack;
    NoshiMediaCache *_media;
    UIImage *_patternImage;
    UIColor *_patternColor;
    void (^_contentHandler)(void);
    NoshiMusicPatternView *_pattern;
    UIImageView *_cover;
    UIImageView *_note;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_artist;
    NoshiMusicKey *_toggle;
    UIButton *_close;
    NSString *_coverKey;
    BOOL _hadContent;
}
@end

@implementation NoshiMusicPill

@synthesize savedTrack = _savedTrack;
@synthesize media = _media;
@synthesize patternImage = _patternImage;
@synthesize patternColor = _patternColor;
@synthesize contentHandler = _contentHandler;

+ (CGFloat)height { return CARD_HEIGHT; }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    /* a row of the white group it stands in, as the songs of telegram for ios 4 were listed: the cover, the title over the artist, and the keys in the accent */
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    _pattern = [[NoshiMusicPatternView alloc] init];
    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.startPoint = CGPointMake(0, 0.5f);
    fade.endPoint = CGPointMake(1, 0.5f);
    fade.colors = [NSArray arrayWithObjects:(id)[UIColor clearColor].CGColor, (id)[UIColor blackColor].CGColor, nil];
    _pattern.layer.mask = fade;
    /* the emoji of a Premium profile stay off the plain row of telegram for ios 4 */
    _pattern.hidden = YES;
    [self addSubview:_pattern];
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 4;
    _cover.backgroundColor = NoshiMusicTonalColor();
    _cover.userInteractionEnabled = NO;
    [self addSubview:_cover];
    _note = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolPlayerNote, 20, NoshiColorAccent())];
    _note.contentMode = UIViewContentModeCenter;
    _note.userInteractionEnabled = NO;
    [self addSubview:_note];
    _title = [[NoshiEmojiLabel alloc] init];
    _title.font = [UIFont systemFontOfSize:17];
    _title.textColor = NoshiColorTitle();
    _title.dropsUndrawable = YES;
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];
    _artist = [[NoshiEmojiLabel alloc] init];
    _artist.font = [UIFont systemFontOfSize:14];
    _artist.textColor = NoshiColorSecondary();
    _artist.dropsUndrawable = YES;
    _artist.userInteractionEnabled = NO;
    [self addSubview:_artist];
    _toggle = [[NoshiMusicKey buttonWithType:UIButtonTypeCustom] retain];
    _toggle.backgroundColor = [UIColor clearColor];
    _toggle.layer.borderWidth = 1;
    _toggle.layer.borderColor = NoshiColorAccent().CGColor;
    [_toggle setRestRadius:KEY_SIDE / 2 animated:NO];
    [_toggle addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_toggle];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:NoshiSymbolImage(NoshiSymbolClose, 14, NoshiColorSecondary()) forState:UIControlStateNormal];
    [_close addTarget:self action:@selector(stopPlayback) forControlEvents:UIControlEventTouchUpInside];
    _close.accessibilityLabel = NSLocalizedString(@"music.stop", nil);
    [self addSubview:_close];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:NoshiMusicPlayerDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_savedTrack release];
    [_media release];
    [_patternImage release];
    [_patternColor release];
    [_contentHandler release];
    [_pattern release];
    [_cover release];
    [_note release];
    [_title release];
    [_artist release];
    [_toggle release];
    [_close release];
    [_coverKey release];
    [super dealloc];
}

/* the controls belong to the profile's own song; a song the person plays from elsewhere must not replace what the profile shows */
- (BOOL)playerActive {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    return player.state != NoshiMusicStateIdle && [player isCurrentTrack:_savedTrack];
}

- (BOOL)hasContent {
    return _savedTrack != nil;
}

- (void)setSavedTrack:(NoshiMedia *)track {
    if (track == _savedTrack) return;
    [_savedTrack release];
    _savedTrack = [track retain];
    [self refresh];
}

- (void)setMedia:(NoshiMediaCache *)media {
    if (media == _media) return;
    [_media release];
    _media = [media retain];
    [self refresh];
}

- (void)setPatternImage:(UIImage *)image {
    if (image == _patternImage) return;
    [_patternImage release];
    _patternImage = [image retain];
    [_pattern setImage:_patternImage color:_patternColor];
}

- (void)setPatternColor:(UIColor *)color {
    if (color == _patternColor) return;
    [_patternColor release];
    _patternColor = [color retain];
    [_pattern setImage:_patternImage color:_patternColor];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

/* shows the saved song, with the controls while it is the one that plays */
- (void)refresh {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    BOOL active = [self playerActive];
    NoshiMedia *shown = _savedTrack;
    BOOL content = shown != nil;
    self.hidden = !content;
    _title.text = shown ? NoshiTrackTitle(shown) : @"";
    NSString *performer = shown ? NoshiTrackPerformer(shown) : @"";
    _artist.text = performer;
    _toggle.hidden = !active;
    _close.hidden = !active;
    if (active) {
        BOOL playing = player.state == NoshiMusicStatePlaying || player.state == NoshiMusicStateLoading;
        [_toggle setImage:NoshiSymbolImage(playing ? NoshiSymbolPause : NoshiSymbolPlay, 14, NoshiColorAccent()) forState:UIControlStateNormal];
        _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    }
    [self loadCoverOf:shown];
    self.accessibilityLabel = shown ? NoshiTrackLine(shown) : nil;
    [self setNeedsLayout];
    if (content != _hadContent) {
        _hadContent = content;
        if (_contentHandler) _contentHandler();
    }
}

/* the cover; a song without a cover, or one that has not come yet, keeps the note */
- (void)loadCoverOf:(NoshiMedia *)track {
    NSString *key = track ? [NSString stringWithFormat:@"%lld:%@:%@", track.size, track.name, track.title] : nil;
    if (key == _coverKey || [key isEqualToString:_coverKey]) return;
    [_coverKey release];
    _coverKey = [key copy];
    _cover.image = nil;
    _note.hidden = NO;
    if (!track || !_media) return;
    NSString *requested = _coverKey;
    [_media loadCoverForTrack:track maxSide:COVER_SIDE * NoshiScreenScale() completion:^(UIImage *image) {
        if (!image || ![requested isEqualToString:_coverKey]) return;
        _cover.image = image;
        _note.hidden = YES;
    }];
}

- (void)togglePlayback {
    [[NoshiMusicPlayer sharedPlayer] togglePause];
}

- (void)stopPlayback {
    [[NoshiMusicPlayer sharedPlayer] stop];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    BOOL active = [self playerActive];
    CGFloat reach = floor(size.width * PATTERN_REACH);
    _pattern.frame = CGRectMake(size.width - reach, 0, reach, size.height);
    /* the marks fade out toward the left edge of their area */
    _pattern.layer.mask.frame = _pattern.bounds;
    _cover.frame = CGRectMake(COVER_INSET, (size.height - COVER_SIDE) / 2, COVER_SIDE, COVER_SIDE);
    _note.frame = _cover.frame;
    CGFloat right = active ? KEY_SIDE + SLOT + 10 : 16;
    CGFloat left = CGRectGetMaxX(_cover.frame) + 12;
    CGFloat width = MAX(0, size.width - left - right);
    BOOL hasArtist = _artist.text.length > 0;
    _title.frame = CGRectMake(left, hasArtist ? 9 : (size.height - 22) / 2, width, 22);
    _artist.frame = CGRectMake(left, 31, width, hasArtist ? 19 : 0);
    _toggle.frame = CGRectMake(size.width - SLOT - KEY_SIDE - 4, (size.height - KEY_SIDE) / 2, KEY_SIDE, KEY_SIDE);
    _close.frame = CGRectMake(size.width - SLOT - 4, 0, SLOT, size.height);
}

@end
