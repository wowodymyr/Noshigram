#import "noshi_gift_compose_controller.h"
#import "noshi_alert_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_custom_emoji_loader.h"
#import "noshi_custom_emoji_picker.h"
#import "noshi_emoji_text_view.h"
#import "noshi_lottie_view.h"
#import "noshi_message.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#include "noshi_folders.h"

#define NOTE_LIMIT 255
#define NOTE_ROW 64.0
#define PICKER_HEIGHT 260.0
#define STICKER_SIDE 132.0

@interface NoshiGiftComposeController () <UITextViewDelegate, UIAlertViewDelegate, NoshiCustomEmojiPickerDelegate> {
    NoshiDialog *_dialog;
    NoshiStarGift *_gift;
    UIScrollView *_scroll;
    UIImageView *_picture;
    NoshiLottieView *_animation;
    UILabel *_name;
    UILabel *_detail;
    UIImageView *_price;
    UILabel *_to;
    UIView *_card;
    NoshiEmojiTextView *_note;
    UILabel *_notePlaceholder;
    /* the custom emoji of the note: the button and the grid that stands in for the keyboard exist for a Premium account only */
    UIButton *_emojiButton;
    NoshiCustomEmojiPicker *_picker;
    NSMutableArray *_noteEmoji;
    BOOL _emojiOpen;
    UILabel *_hideLabel;
    UISwitch *_hide;
    UILabel *_upgradeLabel;
    UISwitch *_upgrade;
    UIButton *_send;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    NoshiPaymentQuote *_quote;
    CGFloat _keyboardOverlap;
    void (^_sentHandler)(void);
}
@end

@implementation NoshiGiftComposeController

@synthesize sentHandler = _sentHandler;

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog gift:(NoshiStarGift *)gift
              avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _gift = [gift retain];
    self.screenTitle = NSLocalizedString(@"gifts.send", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _note.delegate = nil;
    _picker.delegate = nil;
    [_dialog release];
    [_gift release];
    [_scroll release];
    [_picture release];
    [_animation release];
    [_name release];
    [_detail release];
    [_price release];
    [_to release];
    [_card release];
    [_note release];
    [_notePlaceholder release];
    [_emojiButton release];
    [_picker release];
    [_noteEmoji release];
    [_hideLabel release];
    [_hide release];
    [_upgradeLabel release];
    [_upgrade release];
    [_send release];
    [_spinner release];
    [_quote release];
    [_sentHandler release];
    [super dealloc];
}

static UILabel *NoshiComposeLabel(UIColor *color, CGFloat size, BOOL bold) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = bold ? NoshiFontSemibold(size) : NoshiFontRegular(size);
    return label;
}

- (void)buildBodyInView:(UIView *)root {
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = YES;
    [root addSubview:_scroll];
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [_scroll addSubview:_picture];
    _name = NoshiComposeLabel(NoshiColorTitle(), 20, YES);
    _name.textAlignment = NoshiTextAlignmentCenter;
    _name.text = _gift.title.length ? _gift.title : NSLocalizedString(@"gifts.gift", nil);
    [_scroll addSubview:_name];
    _detail = NoshiComposeLabel(NoshiColorSecondary(), 14, NO);
    _detail.textAlignment = NoshiTextAlignmentCenter;
    _detail.text = _gift.limited ? [NSString stringWithFormat:NSLocalizedString(@"gifts.left", nil), (int)_gift.remains, (int)_gift.total] : @"";
    [_scroll addSubview:_detail];
    _price = [[UIImageView alloc] initWithImage:NoshiStarsImage(nil, _gift.stars, NoshiFontSemibold(17), NoshiColorTitle())];
    _price.contentMode = UIViewContentModeCenter;
    [_scroll addSubview:_price];
    _to = NoshiComposeLabel(NoshiColorSecondary(), 14, NO);
    _to.textAlignment = NoshiTextAlignmentCenter;
    _to.text = _dialog.saved ? NSLocalizedString(@"gifts.to.self", nil) : [NSString stringWithFormat:NSLocalizedString(@"gifts.to", nil), _dialog.title];
    [_scroll addSubview:_to];

    _card = [[UIView alloc] init];
    _card.backgroundColor = NoshiColorCard();
    _card.layer.cornerRadius = 12;
    [_scroll addSubview:_card];
    _noteEmoji = [[NSMutableArray alloc] init];
    _note = [[NoshiEmojiTextView alloc] initWithFrame:CGRectZero];
    _note.backgroundColor = [UIColor clearColor];
    _note.emojiBackgroundColor = NoshiColorCard();
    _note.delegate = self;
    _note.font = NoshiFontRegular(16);
    _note.textColor = NoshiColorTitle();
    _note.returnKeyType = UIReturnKeyDone;
    _note.scrollsToTop = NO;
    _note.keyboardAppearance = NoshiThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    [_card addSubview:_note];
    /* a text view draws no placeholder of its own */
    _notePlaceholder = NoshiComposeLabel(NoshiColorMuted(), 16, NO);
    _notePlaceholder.text = NSLocalizedString(@"gifts.note", nil);
    _notePlaceholder.userInteractionEnabled = NO;
    [_card addSubview:_notePlaceholder];
    _emojiButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_emojiButton setImage:NoshiSymbolImage(NoshiSymbolSmiley, 24, NoshiColorAccent()) forState:UIControlStateNormal];
    [_emojiButton addTarget:self action:@selector(emojiTapped) forControlEvents:UIControlEventTouchUpInside];
    _emojiButton.accessibilityLabel = NSLocalizedString(@"gifts.note.emoji", nil);
    _emojiButton.hidden = YES;
    [_card addSubview:_emojiButton];
    [self enableCustomEmojiForPremium];
    _hideLabel = NoshiComposeLabel(NoshiColorTitle(), 16, NO);
    _hideLabel.text = NSLocalizedString(@"gifts.hide", nil);
    _hideLabel.numberOfLines = 0;
    [_card addSubview:_hideLabel];
    _hide = [[UISwitch alloc] init];
    [_card addSubview:_hide];
    if (_gift.upgradeStars > 0) {
        _upgradeLabel = NoshiComposeLabel(NoshiColorTitle(), 16, NO);
        _upgradeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"gifts.upgrade.include", nil), NoshiStarsText(_gift.upgradeStars)];
        _upgradeLabel.numberOfLines = 0;
        [_card addSubview:_upgradeLabel];
        _upgrade = [[UISwitch alloc] init];
        [_card addSubview:_upgrade];
    }
    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _send.backgroundColor = NoshiColorAccent();
    _send.layer.cornerRadius = 12;
    _send.titleLabel.font = NoshiFontSemibold(17);
    [_send setImage:NoshiStarsImage(NSLocalizedString(@"gifts.send.for", nil), _gift.stars, NoshiFontSemibold(17), [UIColor whiteColor]) forState:UIControlStateNormal];
    [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_send];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [_scroll addSubview:_spinner];
    [self showPicture];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

/* the animation plays once its file is here; the thumbnail stands in until then */
- (void)showPicture {
    NoshiMedia *sticker = _gift.sticker;
    NoshiRemoteFile *thumb = sticker.previewFile;
    if (thumb) {
        [self.media loadImageForFile:thumb maxSide:STICKER_SIDE * NoshiScreenScale() completion:^(UIImage *image) {
            if (image && !_animation) _picture.image = image;
        }];
    }
    NoshiRemoteFile *file = sticker.file;
    if (!file || sticker.stickerFormat != NOSHI_STICKER_ANIMATED) return;
    [self retain];
    [self.media loadDataForFile:file completion:^(NSData *data) {
        [self autorelease];
        if (!data) return;
        _animation = [[NoshiLottieView alloc] initWithPackedData:data key:file.key];
        UIImageView *picture = _picture;
        _animation.firstFrameHandler = ^{ picture.image = nil; };
        [_scroll addSubview:_animation];
        [self.view setNeedsLayout];
        [_animation setPlaying:YES];
    }];
}

- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat width = body.size.width;
    CGFloat inner = MIN(width - 32, 460);
    CGFloat x = (width - inner) / 2;
    CGFloat y = 18;
    CGRect sticker = CGRectMake((width - STICKER_SIDE) / 2, y, STICKER_SIDE, STICKER_SIDE);
    _picture.frame = sticker;
    _animation.frame = sticker;
    y += STICKER_SIDE + 8;
    _name.frame = CGRectMake(x, y, inner, 26);
    y += 28;
    _price.frame = CGRectMake(x, y, inner, 24);
    y += 26;
    _detail.frame = CGRectMake(x, y, _gift.limited ? inner : 0, _gift.limited ? 20 : 0);
    y += _gift.limited ? 22 : 0;
    _to.frame = CGRectMake(x, y, inner, 20);
    y += 34;
    CGFloat rows = _upgrade ? 3 : 2;
    _card.frame = CGRectMake(x, y, inner, NOTE_ROW + (rows - 1) * 52);
    CGFloat emojiSide = _emojiButton.hidden ? 0 : 40;
    _note.frame = CGRectMake(8, 6, inner - 16 - emojiSide, NOTE_ROW - 12);
    _notePlaceholder.frame = CGRectMake(14, 0, inner - 28 - emojiSide, NOTE_ROW);
    _emojiButton.frame = CGRectMake(inner - 8 - emojiSide, (NOTE_ROW - 40) / 2, emojiSide, 40);
    _hideLabel.frame = CGRectMake(14, NOTE_ROW, inner - 14 - 70, 52);
    _hide.center = CGPointMake(inner - 14 - _hide.bounds.size.width / 2, NOTE_ROW + 26);
    if (_upgrade) {
        _upgradeLabel.frame = CGRectMake(14, NOTE_ROW + 52, inner - 14 - 70, 52);
        _upgrade.center = CGPointMake(inner - 14 - _upgrade.bounds.size.width / 2, NOTE_ROW + 78);
    }
    y += NOTE_ROW + (rows - 1) * 52 + 22;
    _send.frame = CGRectMake(x, y, inner, 50);
    _spinner.center = CGPointMake(CGRectGetMaxX(_send.frame) - 28, CGRectGetMidY(_send.frame));
    y += 50 + 24;
    _scroll.contentSize = CGSizeMake(width, y);
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, _keyboardOverlap, 0);
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect frame = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:[self.view.window convertRect:frame fromWindow:nil] fromView:nil];
    BOOL showing = [note.name isEqualToString:UIKeyboardWillShowNotification];
    _keyboardOverlap = showing ? MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frame)) : 0;
    [self.view setNeedsLayout];
}

/* custom emoji are the right of a Premium account, so the button waits for the account to say so; the server refuses a note with them from anyone else */
- (void)enableCustomEmojiForPremium {
    [self retain];
    [self.session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        NoshiPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (!me) {
            NSLog(@"noshigram: premium state unknown for the gift note: %@", errorName);
            return;
        }
        if (!me.premium || _picker) return;
        _picker = [[NoshiCustomEmojiPicker alloc] initWithSession:self.session media:self.media];
        _picker.delegate = self;
        _picker.frame = CGRectMake(0, 0, self.view.bounds.size.width, PICKER_HEIGHT);
        _picker.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _emojiButton.hidden = NO;
        [self.view setNeedsLayout];
    }];
}

/* the grid takes the place of the keyboard under the field, and the button brings the keyboard back */
- (void)emojiTapped {
    if (!_picker) return;
    _emojiOpen = !_emojiOpen;
    if (_emojiOpen) [_picker prepare];
    _note.inputView = _emojiOpen ? _picker : nil;
    [_emojiButton setImage:NoshiSymbolImage(_emojiOpen ? NoshiSymbolKeyboard : NoshiSymbolSmiley, 24, NoshiColorAccent()) forState:UIControlStateNormal];
    if ([_note isFirstResponder]) [_note reloadInputViews];
    else [_note becomeFirstResponder];
}

- (void)shiftNoteEmojiForRange:(NSRange)range replacementLength:(NSUInteger)length {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_noteEmoji.count];
    for (NoshiTextEntity *entity in _noteEmoji) {
        size_t offset = entity.range.location;
        if (!noshi_folder_shift_emoji(&offset, entity.range.length, range.location, range.length, length)) continue;
        NoshiTextEntity *moved = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji range:NSMakeRange(offset, entity.range.length) url:nil] autorelease];
        moved.documentId = entity.documentId;
        [kept addObject:moved];
    }
    [_noteEmoji setArray:kept];
}

- (BOOL)textView:(UITextView *)view shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)replacement {
    if ([replacement isEqualToString:@"\n"]) {
        [view resignFirstResponder];
        return NO;
    }
    if (range.location > view.text.length || range.length > view.text.length - range.location) return NO;
    NSString *next = [view.text stringByReplacingCharactersInRange:range withString:replacement];
    if ([next lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > NOTE_LIMIT) return NO;
    [self shiftNoteEmojiForRange:range replacementLength:replacement.length];
    return YES;
}

- (void)textViewDidChange:(UITextView *)view {
    (void)view;
    _note.customEmojiEntities = _noteEmoji;
    _notePlaceholder.hidden = _note.text.length > 0;
}

- (void)customEmojiPicker:(NoshiCustomEmojiPicker *)picker didPickEmoji:(NoshiCustomEmojiDocument *)emoji {
    (void)picker;
    NSRange range = _note.selectedRange;
    NSString *text = _note.text;
    if (emoji.documentId <= 0 || !emoji.alt.length || range.location > text.length || range.length > text.length - range.location) return;
    NSString *next = [text stringByReplacingCharactersInRange:range withString:emoji.alt];
    if ([next lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > NOTE_LIMIT) return;
    [self shiftNoteEmojiForRange:range replacementLength:emoji.alt.length];
    _note.text = next;
    NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji range:NSMakeRange(range.location, emoji.alt.length) url:nil] autorelease];
    entity.documentId = emoji.documentId;
    [_noteEmoji addObject:entity];
    _note.selectedRange = NSMakeRange(range.location + emoji.alt.length, 0);
    [self textViewDidChange:_note];
}

#pragma mark paying

- (void)setWorking:(BOOL)working {
    _working = working;
    _send.enabled = !working;
    _send.alpha = working ? 0.6 : 1;
    if (working) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

- (void)sendTapped {
    if (_working) return;
    [_note resignFirstResponder];
    [self setWorking:YES];
    NSString *raw = _note.text;
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger lead = 0, end = raw.length;
    while (lead < end && [space characterIsMember:[raw characterAtIndex:lead]]) ++lead;
    while (end > lead && [space characterIsMember:[raw characterAtIndex:end - 1]]) --end;
    NSString *note = [raw substringWithRange:NSMakeRange(lead, end - lead)];
    /* the runs count from the start of the trimmed note, and a run the trim cut is not sent */
    NSMutableArray *entities = [NSMutableArray array];
    for (NoshiTextEntity *run in _noteEmoji) {
        if (run.range.location < lead || NSMaxRange(run.range) > end) continue;
        NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji range:NSMakeRange(run.range.location - lead, run.range.length) url:nil] autorelease];
        entity.documentId = run.documentId;
        [entities addObject:entity];
    }
    [self retain];
    [self.session quoteSendingGift:_gift toDialog:_dialog note:note entities:entities hideName:_hide.on includeUpgrade:_upgrade.on completion:^(NoshiPaymentQuote *quote, NSString *errorName) {
        [self autorelease];
        if (!quote) {
            [self setWorking:NO];
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [_quote release];
        _quote = [quote retain];
        Class alertClass = NoshiAlertClass();
        id alert = [[alertClass alloc] initWithTitle:nil
                                             message:[NSString stringWithFormat:NSLocalizedString(@"gifts.confirm", nil), NoshiStarsText(quote.stars), _dialog.saved ? NSLocalizedString(@"gifts.you", nil) : _dialog.title]
                                            delegate:self cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil)
                                   otherButtonTitles:NSLocalizedString(@"gifts.pay", nil), nil];
        [alert show];
        [alert release];
    }];
}

- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    if (index == [alert cancelButtonIndex]) {
        [self setWorking:NO];
        return;
    }
    [self retain];
    [self.session payQuote:_quote completion:^(NSString *errorName) {
        [self autorelease];
        [self setWorking:NO];
        if (errorName) {
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        if (_sentHandler) _sentHandler();
    }];
}

@end
