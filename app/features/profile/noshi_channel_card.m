#import "noshi_channel_card.h"

#import "noshi_avatar_view.h"
#import "noshi_emoji_label.h"
#import "noshi_info_rows.h"
#import "noshi_theme.h"
#import "noshi_time.h"

/* the personal channel as a section of the grouped list of ios 7, the way telegram for ios 4 listed a chat: a grey caption over a white row with the picture,
   the name, the time and the newest post */
#define CAPTION_HEIGHT 30.0
#define ROW_HEIGHT 72.0
#define PICTURE 50.0
#define TEXT_X 77.0

@interface NoshiChannelCard () {
    UILabel *_caption;
    UIView *_plate;
    NoshiAvatarView *_picture;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_last;
    UILabel *_date;
}
@end

@implementation NoshiChannelCard

+ (CGFloat)height { return CAPTION_HEIGHT + ROW_HEIGHT; }

static UILabel *NoshiChannelLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    label.userInteractionEnabled = NO;
    return label;
}

/* the name and the last post are written by other people, so they take the app's own emoji pictures */
static NoshiEmojiLabel *NoshiChannelEmojiLabel(UIColor *color, UIFont *font) {
    NoshiEmojiLabel *label = [[NoshiEmojiLabel alloc] init];
    label.textColor = color;
    label.font = font;
    label.userInteractionEnabled = NO;
    return label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _caption = NoshiChannelLabel(NoshiColorSecondary(), [UIFont systemFontOfSize:14], NoshiTextAlignmentLeft);
    _plate = NoshiNewInfoGroup();
    _plate.userInteractionEnabled = NO;
    _picture = [[NoshiAvatarView alloc] init];
    _picture.userInteractionEnabled = NO;
    _title = NoshiChannelEmojiLabel(NoshiColorTitle(), NoshiFontMedium(17));
    _last = NoshiChannelEmojiLabel(NoshiColorSecondary(), [UIFont systemFontOfSize:15]);
    _last.numberOfLines = 2;
    _date = NoshiChannelLabel(NoshiColorSecondary(), [UIFont systemFontOfSize:14], NoshiTextAlignmentRight);
    for (UIView *view in [NSArray arrayWithObjects:_caption, _plate, _picture, _title, _last, _date, nil]) [self addSubview:view];
    return self;
}

- (void)dealloc {
    [_caption release];
    [_plate release];
    [_picture release];
    [_title release];
    [_last release];
    [_date release];
    [super dealloc];
}

- (void)configureWithChannel:(NoshiPersonalChannel *)channel avatars:(NoshiAvatarCache *)avatars {
    NSString *followers = [NSString stringWithFormat:NSLocalizedString(@"profile.channel.followers", nil), (int)channel.subscribers];
    _caption.text = [[NSString stringWithFormat:@"%@ · %@", NSLocalizedString(@"profile.channel.kind", nil), followers] uppercaseString];
    _picture.initials = channel.dialog.initials;
    _picture.seed = channel.dialog.avatarSeed;
    [_picture setPhoto:channel.dialog.photo cache:avatars];
    _title.text = channel.dialog.title;
    _last.text = channel.lastText;
    _date.text = channel.lastDate ? NoshiListTimeText(channel.lastDate) : @"";
    self.accessibilityLabel = channel.dialog.title;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _caption.frame = CGRectMake(15, CAPTION_HEIGHT - 22, width - 30, 18);
    _plate.frame = CGRectMake(0, CAPTION_HEIGHT, width, ROW_HEIGHT);
    NoshiFitInfoGroupLines(_plate, YES);
    _picture.frame = CGRectMake(15, CAPTION_HEIGHT + floor((ROW_HEIGHT - PICTURE) / 2), PICTURE, PICTURE);
    CGFloat dateWidth = _date.text.length ? ceil([_date sizeThatFits:CGSizeMake(100, 18)].width) : 0;
    _date.frame = CGRectMake(width - 15 - dateWidth, CAPTION_HEIGHT + 11, dateWidth, 18);
    _title.frame = CGRectMake(TEXT_X, CAPTION_HEIGHT + 9, MAX(0, width - TEXT_X - 15 - dateWidth - 6), 22);
    CGFloat lastHeight = MIN(38, ceil([_last sizeThatFits:CGSizeMake(width - TEXT_X - 15, 40)].height));
    _last.frame = CGRectMake(TEXT_X, CAPTION_HEIGHT + 32, width - TEXT_X - 15, lastHeight);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _plate.backgroundColor = highlighted ? (NoshiThemeIsDark() ? [UIColor colorWithWhite:0.25 alpha:1] : [UIColor colorWithWhite:0.85 alpha:1]) : NoshiColorCard();
}

@end
