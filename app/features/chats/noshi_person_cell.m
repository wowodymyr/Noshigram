#import <QuartzCore/QuartzCore.h>
#import "noshi_developers.h"
#import "noshi_name_badge.h"
#import "noshi_emoji_label.h"
#import "noshi_person_cell.h"

#import "noshi_avatar_view.h"
#import "noshi_mutual_icon.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define ROW_HEIGHT 64.0
#define AVATAR_SIZE 44.0
#define SIDE_MARGIN 14.0
#define TAG_HEIGHT 26.0
#define TAG_PADDING 12.0

@interface NoshiPersonCell () {
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_name;
    NoshiEmojiLabel *_subtitle;
    UILabel *_trailing;
    UIImageView *_symbolView;
    UIButton *_mutualButton;
    BOOL _mutual;
    UIView *_line;
    NSUInteger _developer;
    BOOL _premium;
    UIColor *_trailingTint;
}
@end

UIColor *NoshiMemberTagColor(BOOL owner) {
    return owner ? [UIColor colorWithRed:0.49f green:0.43f blue:0.90f alpha:1] : [UIColor colorWithRed:0.25f green:0.75f blue:0.33f alpha:1];
}

@implementation NoshiPersonCell

@synthesize developer = _developer;
@synthesize premium = _premium;
@synthesize mutual = _mutual;
@synthesize trailingTint = _trailingTint;

+ (CGFloat)rowHeight {
    return ROW_HEIGHT;
}

static NoshiEmojiLabel *NoshiPersonEmojiLabel(UIFont *font, NSInteger alignment) {
    NoshiEmojiLabel *label = [[[NoshiEmojiLabel alloc] init] autorelease];
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

static UILabel *NoshiPersonLabel(UIFont *font, NSInteger alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = NoshiColorField();
    self.selectedBackgroundView = selected;
    _avatar = [[NoshiAvatarView alloc] init];
    [self.contentView addSubview:_avatar];
    _name = [NoshiPersonEmojiLabel(NoshiFontSemibold(16.5), NoshiTextAlignmentLeft) retain];
    _name.dropsUndrawable = YES;
    [self.contentView addSubview:_name];
    _subtitle = [NoshiPersonEmojiLabel(NoshiFontRegular(14), NoshiTextAlignmentLeft) retain];
    [self.contentView addSubview:_subtitle];
    _trailing = [NoshiPersonLabel(NoshiFontRegular(13.5), NoshiTextAlignmentRight) retain];
    _trailing.textColor = NoshiColorSecondary();
    _trailing.layer.masksToBounds = YES;
    [self.contentView addSubview:_trailing];
    _symbolView = [[UIImageView alloc] init];
    [self.contentView addSubview:_symbolView];
    _mutualButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _mutualButton.hidden = YES;
    [_mutualButton setImage:NoshiMutualIconImage(24, NoshiColorSecondary()) forState:UIControlStateNormal];
    _mutualButton.accessibilityLabel = NSLocalizedString(@"contact.mutual", nil);
    [_mutualButton addTarget:self action:@selector(mutualTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_mutualButton];
    _line = [[UIView alloc] init];
    _line.backgroundColor = NoshiColorHairline();
    [self.contentView addSubview:_line];
    return self;
}

- (void)dealloc {
    [_trailingTint release];
    [_avatar release];
    [_name release];
    [_subtitle release];
    [_trailing release];
    [_symbolView release];
    [_mutualButton release];
    [_line release];
    [super dealloc];
}

- (void)mutualTapped {
    NoshiShowMutualNotice();
}

- (BOOL)avatarDeleted {
    return _avatar.deleted;
}

- (void)setAvatarDeleted:(BOOL)deleted {
    _avatar.deleted = deleted;
}

- (void)configureWithName:(NSString *)name initials:(NSString *)initials seed:(NSUInteger)seed
                 subtitle:(NSString *)subtitle subtitleColor:(UIColor *)subtitleColor
                 trailing:(NSString *)trailing symbol:(NoshiSymbol)symbol showsSymbol:(BOOL)showsSymbol
              nameColor:(UIColor *)nameColor photo:(NoshiPhoto *)photo avatars:(NoshiAvatarCache *)avatars {
    _avatar.seed = seed;
    _avatar.initials = initials;
    _avatar.deleted = NO;
    /* a reused cell must not keep the glyph an earlier row put in its picture */
    _avatar.showsSymbol = NO;
    [_avatar setPhoto:photo cache:avatars];
    NSArray *badges = nil;
    _name.text = NoshiNameWithBadges(name, NoshiBadgeDocument(0, _premium), _developer, &badges);
    _name.entities = badges;
    _name.dropsUndrawable = YES;
    _developer = 0;
    _premium = NO;
    _name.textColor = nameColor ? nameColor : NoshiColorTitle();
    _subtitle.text = subtitle;
    _subtitle.textColor = subtitleColor ? subtitleColor : NoshiColorSecondary();
    _trailing.text = trailing;
    _trailing.textColor = _trailingTint ? _trailingTint : NoshiColorSecondary();
    _trailing.backgroundColor = _trailingTint ? [_trailingTint colorWithAlphaComponent:0.18f] : [UIColor clearColor];
    _trailing.layer.cornerRadius = _trailingTint ? TAG_HEIGHT / 2 : 0;
    _trailing.textAlignment = _trailingTint ? NoshiTextAlignmentCenter : NoshiTextAlignmentRight;
    self.trailingTint = nil;
    _symbolView.hidden = !showsSymbol;
    if (showsSymbol) _symbolView.image = NoshiSymbolImage(symbol, 22, NoshiColorAccent());
    _mutualButton.hidden = !_mutual;
    _mutual = NO;
    self.accessibilityLabel = subtitle.length ? [NSString stringWithFormat:@"%@, %@", name, subtitle] : name;
    [self setNeedsLayout];
}

- (void)showAvatarSymbol:(NoshiSymbol)symbol {
    _avatar.symbol = symbol;
    _avatar.showsSymbol = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textX = SIDE_MARGIN * 2 + AVATAR_SIZE - 2;
    CGFloat hairline = 1.0 / NoshiScreenScale();
    _avatar.frame = CGRectMake(SIDE_MARGIN, (ROW_HEIGHT - AVATAR_SIZE) / 2, AVATAR_SIZE, AVATAR_SIZE);
    CGFloat right = width - SIDE_MARGIN;
    if (!_mutualButton.hidden) {
        /* the two arrows stand at the end of the row, in a square the finger can find */
        _mutualButton.frame = CGRectMake(width - 44, (ROW_HEIGHT - 44) / 2, 44, 44);
        right = width - 44;
    }
    if (!_symbolView.hidden) {
        CGSize size = _symbolView.image.size;
        _symbolView.frame = CGRectMake(right - size.width, (ROW_HEIGHT - size.height) / 2, size.width, size.height);
        right -= size.width + 8;
    }
    if (_trailing.text.length) {
        BOOL tag = _trailing.layer.cornerRadius > 0;
        CGSize size = [_trailing sizeThatFits:CGSizeMake(120, 20)];
        /* a tag is wider than its text by the padding of the pill, and no wider than a third of the row, so a long post gives way to the name */
        CGFloat shown = tag ? MIN(size.width + 2 * TAG_PADDING, width / 3) : size.width;
        CGFloat height = tag ? TAG_HEIGHT : 20;
        _trailing.frame = CGRectMake(right - shown, (ROW_HEIGHT - height) / 2, shown, height);
        right -= shown + 8;
    } else {
        _trailing.frame = CGRectZero;
    }
    CGFloat textWidth = MAX(0, right - textX);
    if (_subtitle.text.length) {
        _name.frame = CGRectMake(textX, 11, textWidth, 22);
        _subtitle.frame = CGRectMake(textX, 34, textWidth, 19);
    } else {
        _name.frame = CGRectMake(textX, (ROW_HEIGHT - 22) / 2, textWidth, 22);
        _subtitle.frame = CGRectZero;
    }
    _line.frame = CGRectMake(textX, ROW_HEIGHT - hairline, width - textX, hairline);
}

@end
