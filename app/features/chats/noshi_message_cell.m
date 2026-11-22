#import "noshi_custom_emoji.h"
#import "noshi_message_cell.h"
#import "noshi_plural.h"
#import "noshi_map_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_alert.h"
#import "noshi_avatar_view.h"
#import "noshi_emoji_store.h"
#import "noshi_sticker_library.h"
#import "noshi_slots_view.h"
#import "noshi_force_touch.h"
#import "noshi_music_player.h"
#import "noshi_round_playback.h"
#import "noshi_audio_session.h"

/* the swell of a playing video message and its settling back, shared by the circle, its ring and the buttons on it so they move as one */
#define ROUND_SWELL_SECONDS 0.32
#import "noshi_image_decoder.h"
#import "noshi_lottie_view.h"
#import "noshi_gift_card.h"
#import "noshi_media_action_view.h"
#import "noshi_markup_view.h"
#import "noshi_reactions_view.h"
#import "noshi_audio_session.h"
#import "noshi_weak_reference.h"
#import "noshi_lite_mode.h"
#import "noshi_platform.h"
#import "noshi_string_drawing.h"
#import "noshi_symbol.h"
#import "noshi_wave.h"
#import "noshi_chat_settings.h"
#import "noshi_theme.h"
#import "noshi_blur.h"
#import "noshi_classic_bubble.h"
#import "noshi_burn_effect.h"
#include "noshi_message_actions.h"

#define JOIN_RADIUS 5.0
/* the corner of a modern bubble, which the person sets in the chat settings; the corner that tucks in against a neighbour is never larger than it */
static CGFloat NoshiBubbleRadius(void) {
    /* the picture of a classic bubble has the corners of that picture, not the radius the modern bubbles are set to, or a photo cut to the wrong curve shows its own corner
       against the rim of the bubble */
    return NOSHI_CLASSIC_BUBBLE_CORNER;
}
#define MEDIA_BUTTON 48.0
#define VOICE_BUTTON 44.0
#define PAD_X_POLL 11.0
#define META_HEIGHT_POLL 14.0
#define SWIPE_TRIGGER 50.0
#define SWIPE_SHOW 20.0
#define SWIPE_DISC 32.0
#define SWIPE_BACK_SECONDS 0.18
/* how far the rows of others step right to leave room for the selection circle, and the circle's side */
#define SELECT_SHIFT 32.0
#define SELECT_MARK 24.0
static char NoshiGifStatusContext;
/* the comments row of a post: the side padding, the pictures of the commenters and how far each is set over the one before */
#define PAD_X_COMMENTS 11.0
#define COMMENTER_SIDE 24.0
#define COMMENTER_STEP 16.0

typedef enum { NoshiBubbleLayerBody, NoshiBubbleLayerOverlay, NoshiBubbleLayerReply } NoshiBubbleLayer;

/* draws the bubble with its text, or the time capsule over a picture */
/* a picture with a radius of its own at each corner: the corner radius of a layer is one value for the four, so the cut is a mask */
static void NoshiMaskCorners(UIView *view, CGSize size, CGFloat topLeft, CGFloat topRight, CGFloat bottomRight, CGFloat bottomLeft) {
    CGFloat width = size.width, height = size.height;
    CGFloat limit = MIN(width, height) / 2;
    topLeft = MIN(topLeft, limit); topRight = MIN(topRight, limit); bottomRight = MIN(bottomRight, limit); bottomLeft = MIN(bottomLeft, limit);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, topLeft, 0);
    CGPathAddArcToPoint(path, NULL, width, 0, width, topRight, topRight);
    CGPathAddArcToPoint(path, NULL, width, height, width - bottomRight, height, bottomRight);
    CGPathAddArcToPoint(path, NULL, 0, height, 0, height - bottomLeft, bottomLeft);
    CGPathAddArcToPoint(path, NULL, 0, 0, topLeft, 0, topLeft);
    CGPathCloseSubpath(path);
    CAShapeLayer *mask = [view.layer.mask isKindOfClass:[CAShapeLayer class]] ? (CAShapeLayer *)view.layer.mask : nil;
    if (!mask) {
        mask = [CAShapeLayer layer];
        view.layer.mask = mask;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = CGRectMake(0, 0, width, height);
    mask.path = path;
    [CATransaction commit];
    CGPathRelease(path);
}


/* the video layer of a gif sits over the picture and cuts nothing by itself: it takes the corners of the picture, the mask with four radii or the single radius */
static void NoshiMirrorCorners(UIView *view, UIView *source) {
    CAShapeLayer *shape = [source.layer.mask isKindOfClass:[CAShapeLayer class]] ? (CAShapeLayer *)source.layer.mask : nil;
    if (!shape) {
        view.layer.mask = nil;
        view.layer.cornerRadius = source.layer.cornerRadius;
        return;
    }
    view.layer.cornerRadius = 0;
    CAShapeLayer *mask = [view.layer.mask isKindOfClass:[CAShapeLayer class]] ? (CAShapeLayer *)view.layer.mask : nil;
    if (!mask) {
        mask = [CAShapeLayer layer];
        view.layer.mask = mask;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = shape.frame;
    mask.path = shape.path;
    [CATransaction commit];
}

@interface NoshiBubbleView : UIView {
    NoshiChatItem *_item;
    NoshiBubbleLayer _layerKind;
    CGFloat _tailWidth;
    NSString *_fileProgressText;
}
@property (nonatomic, retain) NoshiChatItem *item;
/* the room a classic bubble keeps beside itself for its tail, on the side the bubble leans to; zero without a tail */
@property (nonatomic, assign) CGFloat tailWidth;
/* the part of the text that is selected, in the characters of the laid out string; no length when nothing is */
@property (nonatomic, assign) NSRange pickRange;
@property (nonatomic, assign) NoshiBubbleLayer layerKind;
@property (nonatomic, copy) NSString *fileProgressText;
/* where the bars of a voice note and its speed chip are, in the bubble's coordinates */
- (CGRect)waveRect;
- (CGRect)speedChipRect;
@end

@implementation NoshiBubbleView

@synthesize item = _item;
@synthesize layerKind = _layerKind;
@synthesize tailWidth = _tailWidth;
@synthesize pickRange = _pickRange;
@synthesize fileProgressText = _fileProgressText;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [_item release];
    [_fileProgressText release];
    [super dealloc];
}

static void NoshiAddCorners(CGContextRef context, CGRect rect, CGFloat topLeft, CGFloat topRight, CGFloat bottomRight, CGFloat bottomLeft) {
    CGFloat x0 = CGRectGetMinX(rect), y0 = CGRectGetMinY(rect), x1 = CGRectGetMaxX(rect), y1 = CGRectGetMaxY(rect);
    CGContextMoveToPoint(context, x0 + topLeft, y0);
    CGContextAddLineToPoint(context, x1 - topRight, y0);
    CGContextAddArcToPoint(context, x1, y0, x1, y0 + topRight, topRight);
    CGContextAddLineToPoint(context, x1, y1 - bottomRight);
    CGContextAddArcToPoint(context, x1, y1, x1 - bottomRight, y1, bottomRight);
    CGContextAddLineToPoint(context, x0 + bottomLeft, y1);
    CGContextAddArcToPoint(context, x0, y1, x0, y1 - bottomLeft, bottomLeft);
    CGContextAddLineToPoint(context, x0, y0 + topLeft);
    CGContextAddArcToPoint(context, x0, y0, x0 + topLeft, y0, topLeft);
    CGContextClosePath(context);
}

static void NoshiFillCapsule(CGContextRef context, CGRect rect, UIColor *color) {
    [color setFill];
    NoshiAddCorners(context, rect, rect.size.height / 2, rect.size.height / 2, rect.size.height / 2, rect.size.height / 2);
    CGContextFillPath(context);
}

/* the time and, on our own messages, the delivery mark; color is the one the text beside it uses */
- (void)drawMetaAt:(CGPoint)origin color:(UIColor *)color context:(CGContextRef)context {
    NoshiMessage *message = _item.message;
    [color set];
    CGFloat textWidth = _item.timeSize.width - (message.outgoing ? 20 : 0);
    if (_layerKind == NoshiBubbleLayerOverlay) textWidth = _item.timeSize.width - 10 - (message.outgoing ? 20 : 0);
    CGFloat timeX = origin.x;
    if (_item.authorText.length) {
        /* the name an administrator signed the post with leads the line */
        NoshiDrawStringAt(_item.authorText, NoshiFontRegular(11), CGPointMake(timeX, origin.y));
        timeX += _item.authorWidth;
    }
    if (_item.viewsText.length) {
        /* the view count of a post: a small eye, the count, then the time */
        UIImage *eye = NoshiSymbolImage(NoshiSymbolEye, 12, color);
        [eye drawAtPoint:CGPointMake(timeX, origin.y + 1.5)];
        NoshiDrawStringAt(_item.viewsText, NoshiFontRegular(11), CGPointMake(timeX + 15.5, origin.y));
        timeX += _item.viewsWidth;
    }
    if (_item.deletedWidth > 0) {
        UIImage *can = NoshiSymbolImage(NoshiSymbolTrash, 12, color);
        [can drawAtPoint:CGPointMake(timeX, origin.y + 1 + (12 - can.size.height) / 2)];
        timeX += _item.deletedWidth;
    }
    NoshiDrawStringAt(_item.timeText, NoshiFontRegular(11), CGPointMake(timeX, origin.y));
    if (!message.outgoing) return;
    CGFloat markX = origin.x + ceil(textWidth) + 3;
    CGFloat markY = origin.y + 1;
    if (message.state == NoshiMessageStateFailed) {
        CGRect badge = CGRectMake(markX - 1, markY - 1, 14, 14);
        [NoshiColorBadgeRed() setFill];
        CGContextFillEllipseInRect(context, badge);
        [[UIColor whiteColor] set];
        NoshiDrawStringIn(@"!", NoshiFontBold(10), CGRectMake(badge.origin.x, badge.origin.y - 0.5, badge.size.width, badge.size.height),
                            NoshiStringClip, NoshiTextAlignmentCenter);
        return;
    }
    UIImage *mark;
    if (message.state == NoshiMessageStateSending) mark = NoshiSendingImage(11, color);
    else {
        /* a read mark is lit: the accent control of an imported theme, else the full ink of the line, while a delivered one stays dimmer beside the time */
        UIColor *lit = nil;
        UIColor *markColor = _item.read ? (lit ? lit : color) : [color colorWithAlphaComponent:0.6f];
        mark = NoshiCheckImage(_item.read, 11, markColor);
    }
    /* the slot fits the double check, a single one sits at its right edge */
    CGFloat slot = 11 * 25.0 / 16.0;
    [mark drawAtPoint:CGPointMake(markX + slot - mark.size.width, markY + 0.5 - (mark.size.height - 11) / 2)];
}

- (void)drawPill:(CGContextRef)context {
    CGRect rect = self.bounds;
    NoshiTextLayout *text = _item.pillLayout;
    /* the classic capsule is a plain grey wash, lighter than the modern one so it does not read as a stain on the wallpaper */
    NoshiFillCapsule(context, rect, [UIColor colorWithWhite:0 alpha:NoshiThemeIsDark() ? 0.42 : 0.3]);
    [text drawAtPoint:CGPointMake(11 - _item.pillShift, (rect.size.height - text.size.height) / 2)];
}

#define WAVE_BAR 2.5
#define WAVE_GAP 2.0
#define CHIP_WIDTH 38.0

/* where the bars of a voice note lie in the bubble, and its speed chip, in the bubble's coordinates */
- (CGRect)waveRect {
    CGRect frame = _item.fileFrame;
    return CGRectMake(frame.origin.x + 44 + 10, frame.origin.y + 2, frame.size.width - 44 - 10, 24);
}

- (CGRect)speedChipRect {
    CGRect frame = _item.fileFrame;
    return CGRectMake(CGRectGetMaxX(frame) - CHIP_WIDTH, frame.origin.y + 28, CHIP_WIDTH, 16);
}

/* the note as bars, the part already heard in the strong color, the time and, while it plays, the speed under
   them; a note that came without a waveform gets a flat even row so it still reads as a voice */
- (void)drawVoiceRow:(CGContextRef)context {
    NoshiMessage *message = _item.message;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    BOOL current = [player isCurrentTrack:message.media] && player.state != NoshiMusicStateFailed;
    NSTimeInterval length = current && player.duration > 0 ? player.duration : message.media.duration;
    float heard = current && length > 0 ? (float)MIN(1, player.position / length) : 0;
    CGRect wave = [self waveRect];
    NSData *bars = message.media.waveformBars;
    NSUInteger count = (NSUInteger)MAX(1, floor((wave.size.width + WAVE_GAP) / (WAVE_BAR + WAVE_GAP)));
    UIColor *strong = NoshiColorAccent();
    UIColor *quiet = NoshiColorBubbleMeta(message.outgoing);
    /* a note nobody has played has a ring round its button in the strong color, which fades to a faint one once it is played, so what is new reads at a glance */
    CGRect ring = CGRectInset(CGRectMake(_item.fileFrame.origin.x, _item.fileFrame.origin.y, 44, 44), -3, -3);
    CGContextSaveGState(context);
    CGContextSetStrokeColorWithColor(context, [strong colorWithAlphaComponent:message.mediaUnread ? 1.0 : 0.22].CGColor);
    CGContextSetLineWidth(context, 2);
    CGContextStrokeEllipseInRect(context, CGRectInset(ring, 1, 1));
    CGContextRestoreGState(context);
    const uint8_t *levels = bars.bytes;
    for (NSUInteger i = 0; i < count; ++i) {
        CGFloat level = 0.35;
        if (levels && bars.length) {
            /* each drawn bar shows the loudest of the source bars it covers */
            NSUInteger from = i * bars.length / count, to = MAX(from + 1, (i + 1) * bars.length / count);
            uint8_t peak = 0;
            for (NSUInteger j = from; j < to && j < bars.length; ++j) if (levels[j] > peak) peak = levels[j];
            level = MAX(0.12, peak / 31.0);
        }
        CGFloat height = MAX(3, level * wave.size.height);
        CGFloat x = wave.origin.x + (CGFloat)i * (WAVE_BAR + WAVE_GAP);
        [((CGFloat)(i + 0.5) / (CGFloat)count <= heard ? strong : quiet) setFill];
        NoshiAddCorners(context, CGRectMake(x, CGRectGetMidY(wave) - height / 2, WAVE_BAR, height), WAVE_BAR / 2, WAVE_BAR / 2, WAVE_BAR / 2, WAVE_BAR / 2);
        CGContextFillPath(context);
    }
    NSInteger shown = (NSInteger)(current ? player.position : message.media.duration);
    NSString *time = [NSString stringWithFormat:@"%ld:%02ld", (long)(shown / 60), (long)(shown % 60)];
    [quiet set];
    NoshiDrawStringAt(time, NoshiFontRegular(12), CGPointMake(wave.origin.x, _item.fileFrame.origin.y + 29));
    if (current) {
        CGRect chip = [self speedChipRect];
        [strong setFill];
        NoshiAddCorners(context, chip, 8, 8, 8, 8);
        CGContextFillPath(context);
        [(NoshiColorBubbleIn()) set];
        NoshiDrawStringIn(NoshiSpeedText(player.speed), NoshiFontSemibold(11), CGRectInset(chip, 0, 1), NoshiStringClip, NoshiTextAlignmentCenter);
    }
}

/* the arrow before the second line of a call: up and right for a call of ours, down and left for one that came in */
static void NoshiDrawCallArrow(CGContextRef context, CGPoint origin, BOOL incoming, UIColor *color) {
    const CGFloat side = 10;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, origin.x + side / 2, origin.y + side / 2);
    if (incoming) CGContextRotateCTM(context, (CGFloat)M_PI);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 1.6);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextMoveToPoint(context, -side / 2 + 1, side / 2 - 1);
    CGContextAddLineToPoint(context, side / 2 - 1, -side / 2 + 1);
    CGContextMoveToPoint(context, side / 2 - 5.5f, -side / 2 + 1);
    CGContextAddLineToPoint(context, side / 2 - 1, -side / 2 + 1);
    CGContextAddLineToPoint(context, side / 2 - 1, side / 2 - 5.5f);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

/* a call: its title, under it the arrow and the time with the length, and the phone or the camera at the end of the row */
- (void)drawCallRow:(CGContextRef)context {
    NoshiMessage *message = _item.message;
    CGRect frame = _item.fileFrame;
    UIColor *text = NoshiColorBubbleText(message.outgoing);
    UIColor *line = _item.callFailed ? NoshiColorBadgeRed() : text;
    [_item.fileTitleLayout drawAtPoint:CGPointMake(frame.origin.x, frame.origin.y + 2)];
    NoshiDrawCallArrow(context, CGPointMake(frame.origin.x, frame.origin.y + 28), _item.callIncoming, line);
    [line set];
    NoshiDrawStringIn(_item.fileDetail, NoshiFontRegular(13), CGRectMake(frame.origin.x + 16, frame.origin.y + 25, frame.size.width - 16 - 30, 18), NoshiStringTailTruncate, NoshiTextAlignmentLeft);
    UIImage *glyph = NoshiSymbolImage(_item.callVideo ? NoshiSymbolVideoCamera : NoshiSymbolPhone, 22, text);
    [glyph drawAtPoint:CGPointMake(CGRectGetMaxX(frame) - glyph.size.width, CGRectGetMidY(frame) - glyph.size.height / 2)];
}

- (void)drawFileRow:(CGContextRef)context {
    NoshiMessage *message = _item.message;
    CGRect frame = _item.fileFrame;
    CGRect icon = CGRectMake(frame.origin.x, frame.origin.y, 44, 44);
    if (_item.call) {
        [self drawCallRow:context];
        return;
    }
    /* a one-time file is a card: a disc with a dashed ring and the figure one, whatever the file is */
    if (NoshiMessageIsViewOnce(message)) {
        BOOL expired = NoshiViewOnceExpired(message);
        UIColor *ink = [UIColor whiteColor];
        [(NoshiColorAccent()) setFill];
        CGContextFillEllipseInRect(context, icon);
        CGContextSaveGState(context);
        CGContextSetStrokeColorWithColor(context, [ink colorWithAlphaComponent:expired ? 0.45 : 0.95].CGColor);
        CGContextSetLineWidth(context, 1.6);
        CGFloat dashes[2] = {3.2, 3.2};
        CGContextSetLineDash(context, 0, dashes, 2);
        CGContextStrokeEllipseInRect(context, CGRectInset(icon, 6, 6));
        CGContextRestoreGState(context);
        [ink set];
        NoshiDrawStringIn(@"1", NoshiFontBold(17), CGRectMake(icon.origin.x, icon.origin.y + 11, 44, 22), NoshiStringClip, NoshiTextAlignmentCenter);
        UIColor *quiet = NoshiColorBubbleMeta(message.outgoing);
        CGFloat textX = icon.origin.x + 44 + 10, textWidth = frame.size.width - 44 - 10;
        [_item.fileTitleLayout drawAtPoint:CGPointMake(textX, frame.origin.y + 6)];
        [quiet set];
        NoshiDrawStringIn(_item.fileDetail, NoshiFontRegular(13), CGRectMake(textX, frame.origin.y + 25, textWidth, 18), NoshiStringTailTruncate, NoshiTextAlignmentLeft);
        return;
    }
    /* the button of a voice note, a song or a document is a view of its own over this corner of the row, which animates between its glyphs */
    BOOL ownButton = message.media.kind == NOSHI_PREVIEW_VOICE || message.media.kind == NOSHI_PREVIEW_AUDIO || message.media.kind == NOSHI_PREVIEW_FILE;
    if (!ownButton) {
        [(NoshiColorAccent()) setFill];
        CGContextFillEllipseInRect(context, icon);
        NoshiSymbol glyph = NoshiSymbolDocument;
        switch (message.media.kind) {
        case NOSHI_PREVIEW_FILE: glyph = NoshiSymbolArrowDown; break;
        case NOSHI_PREVIEW_VIDEO:
        case NOSHI_PREVIEW_VIDEO_MESSAGE:
        case NOSHI_PREVIEW_GIF: glyph = NoshiSymbolPlay; break;
        default: break;
        }
        UIImage *symbol = NoshiSymbolImage(glyph, 22, [UIColor whiteColor]);
        [symbol drawAtPoint:CGPointMake(icon.origin.x + (44 - symbol.size.width) / 2, icon.origin.y + (44 - symbol.size.height) / 2)];
    }
    if (message.media.kind == NOSHI_PREVIEW_VOICE) {
        [self drawVoiceRow:context];
        return;
    }
    UIColor *quiet = NoshiColorBubbleMeta(message.outgoing);
    CGFloat textX = icon.origin.x + 44 + 10, textWidth = frame.size.width - 44 - 10;
    [_item.fileTitleLayout drawAtPoint:CGPointMake(textX, frame.origin.y + 6)];
    [quiet set];
    if (!_fileProgressText && _item.fileDetailLayout) [_item.fileDetailLayout drawAtPoint:CGPointMake(textX, frame.origin.y + 25)];
    else NoshiDrawStringIn(_fileProgressText ? _fileProgressText : _item.fileDetail, NoshiFontRegular(13), CGRectMake(textX, frame.origin.y + 25, textWidth, 18), NoshiStringTailTruncate, NoshiTextAlignmentLeft);
}

- (void)drawReply {
    if (CGRectIsEmpty(_item.replyFrame)) return;
    CGRect frame = _layerKind == NoshiBubbleLayerReply ? self.bounds : _item.replyFrame;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:10] addClip];
    UIColor *bubbleColor = _item.message.outgoing ? NoshiColorBubbleOut() : NoshiColorBubbleIn();
    if (_layerKind == NoshiBubbleLayerReply) {
        [bubbleColor setFill];
        UIRectFill(frame);
    }
    if (NoshiChatFlagGet(NoshiChatFlagReplyBackground)) {
        /* the plate of a quote in our own classic bubble carries more of the accent, so it does not fade into the bubble */
        [NoshiMixedColor(bubbleColor, _item.replyColor, _item.message.outgoing ? 0.42 : 0.3) setFill];
        UIRectFill(frame);
    }
    CGContextRestoreGState(context);
    /* the bar is a pill inset from the edge of the plate */
    [_item.replyColor setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(frame.origin.x + 6, frame.origin.y + 6, 3, MAX(0, frame.size.height - 12)) cornerRadius:1.5] fill];
    CGPoint at = CGPointMake(frame.origin.x + 17, frame.origin.y + 6);
    [_item.replyTitleLayout drawAtPoint:at];
    at.y += _item.replyTitleLayout.size.height + 2;
    [_item.replyTextLayout drawAtPoint:at];
}

- (void)drawBody:(CGContextRef)context {
    if (_item.bare) {
        /* the emoji stands on the wallpaper; its time is on the plate over it */
        [_item.textLayout drawAtPoint:_item.textOrigin];
        return;
    }
    NoshiMessage *message = _item.message;
    BOOL outgoing = message.outgoing;
    /* the picture holds the tail, so it takes the whole bounds, which are as wide as the bubble and its tail */
    UIImage *bubble = NoshiClassicBubbleImage(outgoing, _tailWidth > 0);
    [bubble drawInRect:self.bounds];
    /* the content is laid out from the bubble's own corner, so a bubble with its tail on the left slides over by the tail */
    if (_tailWidth > 0 && !outgoing) CGContextTranslateCTM(context, _tailWidth, 0);
    if (_item.senderName.length) {
        [_item.senderLayout drawAtPoint:_item.senderOrigin];
        [_item.senderTagLayout drawAtPoint:_item.senderTagOrigin];
    }
    if (_item.viaText.length) [_item.viaLayout drawAtPoint:_item.viaOrigin];
    if (_item.forwardText.length) {
        [_item.forwardLayout drawAtPoint:_item.forwardOrigin];
    }
    [self drawReply];
    if (_item.content == NoshiChatItemContentFile) [self drawFileRow:context];
    if (_item.content == NoshiChatItemContentPoll) [self drawPoll:context];
    if (_item.textLayout && _pickRange.length) {
        /* a quarter of the text color mixed into the bubble keeps the text readable on any bubble color; an accent at partial alpha turned a custom bubble into a washed patch the text got lost on */
        [NoshiMixedColor(outgoing ? NoshiColorBubbleOut() : NoshiColorBubbleIn(), NoshiColorBubbleText(outgoing), 0.25) setFill];
        for (NSValue *box in [_item.textLayout rectsForRange:_pickRange]) UIRectFill(CGRectOffset(box.CGRectValue, _item.textOrigin.x, _item.textOrigin.y));
    }
    if (_item.textLayout) {
        CGContextSaveGState(context);
        [_item.textLayout drawAtPoint:_item.textOrigin];
        CGContextRestoreGState(context);
    }
    if (_item.textLayout && _pickRange.length) {
        NSArray *boxes = [_item.textLayout rectsForRange:_pickRange];
        if (boxes.count) {
            CGRect first = [[boxes objectAtIndex:0] CGRectValue], last = [[boxes lastObject] CGRectValue];
            [NoshiColorBubbleLink(outgoing) setFill];
            CGFloat left = _item.textOrigin.x + first.origin.x, top = _item.textOrigin.y + first.origin.y;
            CGFloat right = _item.textOrigin.x + CGRectGetMaxX(last), bottom = _item.textOrigin.y + CGRectGetMaxY(last);
            UIRectFill(CGRectMake(left - 1, top, 2, first.size.height));
            UIRectFill(CGRectMake(right - 1, bottom - last.size.height, 2, last.size.height));
            CGContextFillEllipseInRect(context, CGRectMake(left - 4.5, top - 8, 9, 9));
            CGContextFillEllipseInRect(context, CGRectMake(right - 4.5, bottom - 1, 9, 9));
        }
    }
    BOOL overPicture = _item.content == NoshiChatItemContentPicture && (!_item.textLayout || _item.captionAbove);
    /* the time of a call is in its second line */
    if (!overPicture && !_item.call) [self drawMetaAt:_item.timeOrigin color:NoshiColorBubbleMeta(outgoing) context:context];
    if (_item.commentsText.length) [self drawCommentsRow:context];
}

/* a check or a cross in a filled disc, 20 points wide */
static void NoshiDrawPollMark(CGContextRef context, CGRect mark, UIColor *fill, UIColor *glyphColor, NoshiSymbol symbol, BOOL square) {
    [fill setFill];
    if (square) {
        NoshiAddCorners(context, mark, 5, 5, 5, 5);
        CGContextFillPath(context);
    } else {
        CGContextFillEllipseInRect(context, mark);
    }
    UIImage *glyph = NoshiSymbolImage(symbol, 13, glyphColor);
    [glyph drawAtPoint:CGPointMake(CGRectGetMidX(mark) - glyph.size.width / 2, CGRectGetMidY(mark) - glyph.size.height / 2)];
}


- (void)drawPoll:(CGContextRef)context {
    NoshiMessage *message = _item.message;
    NoshiPoll *poll = message.poll;
    BOOL outgoing = message.outgoing;
    UIColor *text = NoshiColorBubbleText(outgoing), *quiet = NoshiColorBubbleMeta(outgoing), *accent = NoshiColorBubbleLink(outgoing);
    UIColor *good = [UIColor colorWithRed:0.30f green:0.73f blue:0.35f alpha:1], *bad = NoshiColorBadgeRed();
    /* the mark of a chosen answer is a light disc on the purple of an outgoing bubble, where a white check would vanish, so its glyph takes the color of the bubble */
    UIColor *glyph = outgoing ? NoshiColorBubbleOut() : [UIColor whiteColor];
    [_item.pollQuestionLayout drawAtPoint:_item.pollQuestionOrigin];
    [_item.pollKindLayout drawAtPoint:_item.pollKindOrigin];
    BOOL results = _item.pollShowsResults;
    int32_t most = 0;
    for (NoshiPollAnswer *answer in poll.answers) most = MAX(most, answer.voters);
    for (NSUInteger i = 0; i < poll.answers.count; ++i) {
        NoshiPollAnswer *answer = [poll.answers objectAtIndex:i];
        NoshiTextLayout *layout = [_item.pollAnswerLayouts objectAtIndex:i];
        CGRect row = [[_item.pollAnswerFrames objectAtIndex:i] CGRectValue];
        CGRect mark = CGRectMake(row.origin.x, row.origin.y + 8, 20, 20);
        BOOL picked = [poll.picked containsIndex:i];
        BOOL show = results && poll.voted;
        if (poll.quiz && show && answer.correct) NoshiDrawPollMark(context, mark, good, [UIColor whiteColor], NoshiSymbolCheck, NO);
        else if (poll.quiz && show && answer.chosen) NoshiDrawPollMark(context, mark, bad, [UIColor whiteColor], NoshiSymbolClose, NO);
        else if (answer.chosen || picked) NoshiDrawPollMark(context, mark, accent, glyph, NoshiSymbolCheck, poll.multiple);
        else {
            [quiet setStroke];
            CGContextSetLineWidth(context, 1.5);
            CGRect ring = CGRectInset(mark, 0.75, 0.75);
            if (poll.multiple) {
                NoshiAddCorners(context, ring, 5, 5, 5, 5);
                CGContextStrokePath(context);
            } else {
                CGContextStrokeEllipseInRect(context, ring);
            }
        }
        CGFloat textX = row.origin.x + 20 + 8;
        [layout drawAtPoint:CGPointMake(textX, row.origin.y + 8)];
        if (!results) continue;
        int32_t total = MAX(poll.totalVoters, 1);
        CGFloat share = (CGFloat)answer.voters / (CGFloat)total;
        NSString *percent = [NSString stringWithFormat:@"%d%%", (int)(share * 100 + 0.5f)];
        [text set];
        NoshiDrawStringIn(percent, NoshiFontSemibold(13), CGRectMake(CGRectGetMaxX(row) - 38, row.origin.y + 8, 38, 20), NoshiStringClip, NoshiTextAlignmentRight);
        /* the bar is as long as the answer's share of the longest, so a poll of one answer still reads as a full bar */
        CGFloat barWidth = row.size.width - 20 - 8 - 38;
        CGFloat barY = CGRectGetMaxY(row) - 8 - 4 - (poll.hasCounts ? NOSHI_POLL_VOTES_LINE : 0);
        CGFloat fraction = most > 0 ? (CGFloat)answer.voters / (CGFloat)most : 0;
        UIColor *barColor = poll.quiz && show && answer.correct ? good : (poll.quiz && show && answer.chosen ? bad : accent);
        if (poll.hasCounts) {
            NSString *votes = [NSString stringWithFormat:NSLocalizedString([@"poll.votes." stringByAppendingString:NoshiPluralForm(answer.voters)], nil), (int)answer.voters];
            [quiet set];
            NoshiDrawStringIn(votes, NoshiFontRegular(12), CGRectMake(textX, barY + 4 + 2, row.size.width - 20 - 8, 14), NoshiStringTailTruncate, NoshiTextAlignmentLeft);
        }
        [[barColor colorWithAlphaComponent:0.25f] setFill];
        NoshiAddCorners(context, CGRectMake(textX, barY, barWidth, 4), 2, 2, 2, 2);
        CGContextFillPath(context);
        if (fraction > 0) {
            [barColor setFill];
            NoshiAddCorners(context, CGRectMake(textX, barY, MAX(4, barWidth * fraction), 4), 2, 2, 2, 2);
            CGContextFillPath(context);
        }
    }
    if (_item.pollButtonTitle.length) {
        CGRect button = _item.pollButtonFrame;
        [[quiet colorWithAlphaComponent:0.25f] setFill];
        CGContextFillRect(context, CGRectMake(button.origin.x, button.origin.y, button.size.width, 1.0 / NoshiScreenScale()));
        [accent set];
        NoshiDrawStringIn(_item.pollButtonTitle, NoshiFontSemibold(15), CGRectMake(button.origin.x, button.origin.y + 8, button.size.width, 20), NoshiStringClip, NoshiTextAlignmentCenter);
    }
    [quiet set];
    CGFloat footerY = _item.pollFooterOwnRow ? _item.pollFooterY : _item.timeOrigin.y;
    NoshiDrawStringAt(_item.pollFooterText, NoshiFontRegular(12), CGPointMake(PAD_X_POLL + NoshiPollVotersWidth(MIN(_item.pollVoterPeople.count, (NSUInteger)3)), footerY));
}

/* the comments of a post: a hairline over the row, the newest commenters' pictures at the left (views of their own), the count in the
   accent color, and a chevron at the right end */
- (void)drawCommentsRow:(CGContextRef)context {
    CGRect row = _item.commentsFrame;
    BOOL outgoing = _item.message.outgoing;
    [[NoshiColorBubbleMeta(outgoing) colorWithAlphaComponent:0.25] setFill];
    CGContextFillRect(context, CGRectMake(row.origin.x + PAD_X_COMMENTS, row.origin.y, row.size.width - 2 * PAD_X_COMMENTS, 1.0 / NoshiScreenScale()));
    NSUInteger shown = MIN(_item.commenterPeople.count, (NSUInteger)3);
    CGFloat textX = row.origin.x + PAD_X_COMMENTS + (shown ? COMMENTER_SIDE + (CGFloat)(shown - 1) * COMMENTER_STEP + 8 : 0);
    UIColor *accent = NoshiColorBubbleLink(outgoing);
    [accent set];
    CGSize text = NoshiStringSize(_item.commentsText, NoshiFontSemibold(14));
    UIImage *chevron = NoshiSymbolImage(NoshiSymbolChevronRight, 14, accent);
    /* the words end before the arrow: a row that is too narrow for them is cut with dots and does not run into it */
    CGFloat room = MAX(0, CGRectGetMaxX(row) - PAD_X_COMMENTS - chevron.size.width - 8 - textX);
    NoshiDrawStringIn(_item.commentsText, NoshiFontSemibold(14), CGRectMake(textX, row.origin.y + (row.size.height - text.height) / 2, MIN(room, ceil(text.width)), text.height), NoshiStringTailTruncate, NoshiTextAlignmentLeft);
    [chevron drawAtPoint:CGPointMake(CGRectGetMaxX(row) - PAD_X_COMMENTS - chevron.size.width, row.origin.y + (row.size.height - chevron.size.height) / 2)];
}

- (void)drawOverlay:(CGContextRef)context {
    CGRect capsule = CGRectMake(0, 0, _item.timeSize.width, _item.timeSize.height);
    NoshiFillCapsule(context, capsule, NoshiColorBubbleCapsule());
    [self drawMetaAt:CGPointMake(5, 2.5) color:[UIColor whiteColor] context:context];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_item) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    NSUInteger misses = NoshiEmojiMissCount();
    NSUInteger animated = NoshiCustomEmojiAnimatedDraws();
    if (_layerKind == NoshiBubbleLayerReply) [self drawReply];
    else if (_layerKind == NoshiBubbleLayerOverlay) [self drawOverlay:context];
    else if (_item.kind == NoshiChatItemPill && !_item.giftCard) [self drawPill:context];
    else if (_item.kind == NoshiChatItemBubble) [self drawBody:context];
    else if (_item.commentsText.length) {
        CGRect row = _item.commentsFrame;
        [(_item.message.outgoing ? NoshiColorBubbleOut() : NoshiColorBubbleIn()) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:row cornerRadius:NoshiBubbleRadius()] fill];
        [self drawCommentsRow:context];
    }
    if (NoshiEmojiMissCount() != misses) NoshiEmojiRedrawWhenLoaded(self);
    if (NoshiCustomEmojiAnimatedDraws() != animated) [NoshiCustomEmoji keepAnimatingView:self];
    /* a sticker has no bubble, its picture and the time capsule over it are other views */
}

@end

/* the spoiler over a photo or a video its sender hid */
#define SPOILER_FPS_INTERVAL 2
#define SPOILER_SPECK 1.4
#define SPOILER_LEVELS 3

@interface NoshiSpoilerTicker : NSObject {
    NoshiWeakReference *_target;
}
- (id)initWithTarget:(id)target;
- (void)tick:(CADisplayLink *)link;
@end

@interface NoshiSpoilerCover : UIView {
    UIImageView *_source;
    UIImage *_blurred;
    UIImage *_blurredFrom;
    CADisplayLink *_link;
    NoshiSpoilerTicker *_ticker;
    CGPoint *_position;
    CGPoint *_motion;
    float *_age;
    float *_life;
    uint8_t *_level;
    NSUInteger _count;
    CFTimeInterval _last;
    BOOL _revealing;
    CFTimeInterval _revealStart;
    CFTimeInterval _revealLength;
    CGPoint _revealCenter;
    CGFloat _revealReach;
    void (^_revealDone)(void);
}
/* the picture that is covered; its image is blurred for the plate and follows it when it arrives late */
@property (nonatomic, assign) UIImageView *source;
/* lifts the cover from a point in its own coordinates, and runs done when the circle has covered it all */
- (void)revealFromPoint:(CGPoint)point done:(void (^)(void))done;
- (void)step:(CADisplayLink *)link;
@end

@implementation NoshiSpoilerTicker
- (id)initWithTarget:(id)target {
    self = [super init];
    if (!self) return nil;
    _target = [[NoshiWeakReference referenceTo:target] retain];
    return self;
}
- (void)dealloc {
    [_target release];
    [super dealloc];
}
- (void)tick:(CADisplayLink *)link {
    [(NoshiSpoilerCover *)_target.target step:link];
}
@end

@implementation NoshiSpoilerCover

@synthesize source = _source;

static float NoshiSpoilerRandom(void) {
    return (float)arc4random() / 4294967296.0f;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.clipsToBounds = YES;
    self.contentMode = UIViewContentModeRedraw;
    _ticker = [[NoshiSpoilerTicker alloc] initWithTarget:self];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_ticker release];
    [_blurred release];
    [_blurredFrom release];
    [_revealDone release];
    free(_position);
    free(_motion);
    free(_age);
    free(_life);
    free(_level);
    [super dealloc];
}

/* a speck starts somewhere in the plate and goes off at a speed of eight to twenty points a second in a direction of its own */
- (void)respawn:(NSUInteger)index {
    CGSize size = self.bounds.size;
    float angle = NoshiSpoilerRandom() * 2 * (float)M_PI;
    float speed = (4 + NoshiSpoilerRandom() * 6) * 2;
    _position[index] = CGPointMake(NoshiSpoilerRandom() * (float)size.width, NoshiSpoilerRandom() * (float)size.height);
    _motion[index] = CGPointMake(cosf(angle) * speed, sinf(angle) * speed);
    _age[index] = 0;
    _life[index] = 1 + NoshiSpoilerRandom() * 2;
    _level[index] = (uint8_t)(arc4random() % SPOILER_LEVELS);
}

/* a speck for about every hundred and fifty square points, as many as an old phone draws at thirty frames */
- (void)resizeSwarm {
    CGSize size = self.bounds.size;
    NSUInteger want = (NSUInteger)MIN(450.0, MAX(0.0, size.width * size.height / 150.0));
    if (want == _count) return;
    free(_position); free(_motion); free(_age); free(_life); free(_level);
    _count = want;
    _position = calloc(want ? want : 1, sizeof(CGPoint));
    _motion = calloc(want ? want : 1, sizeof(CGPoint));
    _age = calloc(want ? want : 1, sizeof(float));
    _life = calloc(want ? want : 1, sizeof(float));
    _level = calloc(want ? want : 1, sizeof(uint8_t));
    if (!_position || !_motion || !_age || !_life || !_level) {
        _count = 0;
        return;
    }
    for (NSUInteger i = 0; i < want; ++i) {
        [self respawn:i];
        /* the first frame has them at every point of their life, so the swarm does not pulse in step */
        _age[i] = NoshiSpoilerRandom() * _life[i];
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self resizeSwarm];
}

- (BOOL)animates {
    return NoshiLiteEnabled(NOSHI_LITE_CHAT_SPOILER) && !NoshiReduceMotionEnabled();
}

- (void)updateLink {
    BOOL run = self.window && !self.hidden && (_revealing || [self animates]);
    if (run && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:_ticker selector:@selector(tick:)];
        NoshiSetFrameRate(_link, 60 / SPOILER_FPS_INTERVAL);
        _last = 0;
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else if (!run && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateLink];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateLink];
}

- (void)step:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CFTimeInterval dt = _last ? MIN(0.1, now - _last) : 0;
    _last = now;
    CGSize size = self.bounds.size;
    for (NSUInteger i = 0; i < _count; ++i) {
        _age[i] += (float)dt;
        _position[i].x += _motion[i].x * (float)dt;
        _position[i].y += _motion[i].y * (float)dt;
        if (_age[i] >= _life[i] || _position[i].x < 0 || _position[i].y < 0 || _position[i].x > size.width || _position[i].y > size.height) [self respawn:i];
    }
    if (_revealing && now - _revealStart >= _revealLength) {
        _revealing = NO;
        void (^done)(void) = [_revealDone retain];
        [_revealDone release];
        _revealDone = nil;
        [self updateLink];
        if (done) done();
        [done release];
        return;
    }
    [self setNeedsDisplay];
}

- (void)revealFromPoint:(CGPoint)point done:(void (^)(void))done {
    CGSize size = self.bounds.size;
    CGFloat reach = 0;
    CGPoint corners[4] = {CGPointMake(0, 0), CGPointMake(size.width, 0), CGPointMake(0, size.height), CGPointMake(size.width, size.height)};
    for (int i = 0; i < 4; ++i) reach = MAX(reach, hypot(corners[i].x - point.x, corners[i].y - point.y));
    _revealCenter = point;
    _revealReach = reach;
    /* the time: three tenths of a millisecond for each point of reach, between a quarter and just over half a
       second */
    _revealLength = MIN(550.0, MAX(250.0, reach * 0.3)) / 1000.0;
    _revealStart = CACurrentMediaTime();
    _revealing = YES;
    [_revealDone release];
    _revealDone = [done copy];
    [self updateLink];
    [self setNeedsDisplay];
}

/* the picture shrunk to a few dozen points, box blurred, and drawn large again; the shrunk picture alone shows as blocks when it is stretched, which reads as
   pixelation and not as a blur */
- (UIImage *)blurredPlate {
    UIImage *image = _source.image;
    if (!image || !NoshiLiteEnabled(NOSHI_LITE_CHAT_BLUR)) return nil;
    if (image == _blurredFrom && _blurred) return _blurred;
    CGSize size = image.size;
    if (size.width < 1 || size.height < 1) return nil;
    CGFloat scale = MIN(1, 28.0 / MAX(size.width, size.height));
    CGSize small = CGSizeMake(MAX(2, floor(size.width * scale)), MAX(2, floor(size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(small, YES, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [image drawInRect:CGRectMake(0, 0, small.width, small.height)];
    UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (made) made = NoshiBoxBlurredImage(made, 2, 2);
    [_blurred release];
    _blurred = [made retain];
    [_blurredFrom release];
    _blurredFrom = [image retain];
    return _blurred;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat progress = 0;
    CGContextSaveGState(context);
    if (_revealing) {
        progress = MIN(1, (CACurrentMediaTime() - _revealStart) / _revealLength);
        /* what stays is everything outside the circle that grows from the finger */
        CGContextBeginPath(context);
        CGContextAddRect(context, bounds);
        CGContextAddEllipseInRect(context, CGRectMake(_revealCenter.x - _revealReach * progress, _revealCenter.y - _revealReach * progress,
                                                      2 * _revealReach * progress, 2 * _revealReach * progress));
        CGContextEOClip(context);
    }
    UIImage *plate = [self blurredPlate];
    if (plate) {
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        /* the plate fills the frame the way the picture does, cropped at its long side */
        CGFloat fill = MAX(bounds.size.width / plate.size.width, bounds.size.height / plate.size.height);
        CGSize drawn = CGSizeMake(plate.size.width * fill, plate.size.height * fill);
        [plate drawInRect:CGRectMake((bounds.size.width - drawn.width) / 2, (bounds.size.height - drawn.height) / 2, drawn.width, drawn.height)];
        [[UIColor colorWithWhite:0 alpha:0.28] setFill];
        CGContextFillRect(context, bounds);
    } else {
        [[UIColor colorWithRed:0.18 green:0.19 blue:0.22 alpha:1] setFill];
        CGContextFillRect(context, bounds);
    }
    static const CGFloat strengths[SPOILER_LEVELS] = {0.3, 0.6, 1.0};
    for (int level = 0; level < SPOILER_LEVELS; ++level) {
        [[UIColor colorWithWhite:1 alpha:strengths[level] * (1 - progress)] setFill];
        for (NSUInteger i = 0; i < _count; ++i) {
            if (_level[i] != level) continue;
            CGContextFillRect(context, CGRectMake(_position[i].x, _position[i].y, SPOILER_SPECK, SPOILER_SPECK));
        }
    }
    CGContextRestoreGState(context);
}

@end

@interface NoshiMessageCell () <UIGestureRecognizerDelegate> {
    NoshiSpoilerCover *_spoilerCover;
    /* the band that lights the row of a message the list scrolled to */
    UIView *_flash;
    UIPanGestureRecognizer *_swipe;
    UIPanGestureRecognizer *_seekPan;
    UIView *_swipeDisc;
    CAShapeLayer *_swipeRing;
    CALayer *_swipeFill;
    BOOL _swipeShown;
    BOOL _swipeArmed;
    CGFloat _swipePull;
    NSUInteger _swipeGeneration;
    UIControl *_selectCover;
    UIView *_selectMark;
    UIImageView *_selectCheck;
    BOOL _selecting;
    NSRange _pick;
    CGPoint _pressPoint;
    UIPanGestureRecognizer *_handlePan;
    NSInteger _dragHandle;
    BOOL _selected;
    NoshiChatItem *_item;
    NoshiBubbleView *_body;
    /* the bubble grows to the height a new reaction row gives it on its own clock, since the body is drawn at its bounds and a layer animation would stretch the text */
    CADisplayLink *_growLink;
    CFTimeInterval _growStart;
    CGFloat _growFrom;
    CGFloat _growTo;
    NoshiBubbleView *_replyPreview;
    NoshiBubbleView *_overlay;
    UIImageView *_picture;
    NoshiMapView *_map;
    UILabel *_gifLabel;
    /* the button over a video, a round message and a picture that is still on its way */
    NoshiMediaActionView *_play;
    /* the button of a voice note or a song, at the front of its row */
    NoshiMediaActionView *_voiceAction;
    NoshiRoundVideoView *_gifView;
    AVPlayer *_gifPlayer;
    AVPlayerItem *_gifItem;
    NSURL *_gifURL;
    BOOL _gifFailed;
    BOOL _gifPlayRequested;
    /* the file behind the button: where it is once it is here, the request that brings it, and what a tap does when it arrives */
    NSString *_loadedPath;
    NSUInteger _loadRequest;
    NSUInteger _loadToken;
    BOOL _loadAsked;
    BOOL _loadFailed;
    float _loadProgress;
    BOOL _playWhenLoaded;
    BOOL _photoLoadShown;
    NoshiLottieView *_lottie;
    /* the slot machine of a 🎰 message, in the place of the single animation */
    NoshiSlotsView *_slots;
    NoshiGiftCardView *_giftCardView;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickerLibrary;
    BOOL _emojiPlayed;
    BOOL _replayRequested;
    BOOL _animationLoading;
    NoshiAvatarView *_avatar;
    UIButton *_avatarButton;
    UIButton *_senderButton;
    NoshiAvatarCache *_avatars;
    NSUInteger _token;
    BOOL _animating;
    NoshiRoundVideoView *_roundView;
    UIButton *_roundSpeed;
    CAShapeLayer *_roundRing;
    NSTimer *_roundTimer;
    /* owned by the content view; read to keep a hard press and a long press of one touch from opening the menu twice */
    UIGestureRecognizer *_longPress;
    UIGestureRecognizer *_forcePress;
    NoshiReactionsView *_reactions;
    int32_t _reactionsMessageId;
    NSString *_reactionsKey;
    /* the pictures of an album, one view each, made as albums come and shown as far as the album has pictures */
    NSMutableArray *_albumViews;
    NSMutableArray *_albumMarks;
    NoshiMessage *_tappedMedia;
    UITapGestureRecognizer *_doubleTap;
    NoshiMarkupView *_markupView;
    NSMutableArray *_commenters;
    NSMutableArray *_pollVoters;
    UIButton *_share;
    UIButton *_sharingAccept;
    UIButton *_sharingDecline;
    NoshiWeakReference *_weak;
    BOOL _activationDeferred;
    UIPanGestureRecognizer *_pausedTablePan;
    /* the sticker file that arrived while activation was deferred */
    NSData *_pendingLottie;
    NSString *_pendingLottieKey;
}
- (void)resumeReplyTable;
- (void)growBodyStep:(CADisplayLink *)link;
- (void)stopBodyGrowth;
@end

#define BODY_GROW_SECONDS 0.25

@interface NoshiBodyGrowTicker : NSObject {
    NoshiWeakReference *_target;
}
- (id)initWithTarget:(id)target;
- (void)tick:(CADisplayLink *)link;
@end

@implementation NoshiBodyGrowTicker
- (id)initWithTarget:(id)target {
    self = [super init];
    if (!self) return nil;
    _target = [[NoshiWeakReference referenceTo:target] retain];
    return self;
}
- (void)dealloc {
    [_target release];
    [super dealloc];
}
- (void)tick:(CADisplayLink *)link {
    [(NoshiMessageCell *)_target.target growBodyStep:link];
}
@end

@implementation NoshiMessageCell

@synthesize delegate = _delegate;
@synthesize item = _item;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _body = [[NoshiBubbleView alloc] init];
    [self.contentView addSubview:_body];
    _replyPreview = [[NoshiBubbleView alloc] init];
    _replyPreview.layerKind = NoshiBubbleLayerReply;
    _replyPreview.userInteractionEnabled = NO;
    [self.contentView addSubview:_replyPreview];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.hidden = YES;
    [self.contentView addSubview:_avatar];
    _avatarButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_avatarButton addTarget:self action:@selector(senderTapped:event:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_avatarButton];
    _senderButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_senderButton addTarget:self action:@selector(senderTapped:event:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_senderButton];
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    [self.contentView addSubview:_picture];
    _play = [[NoshiMediaActionView alloc] initWithFrame:CGRectMake(0, 0, MEDIA_BUTTON, MEDIA_BUTTON)];
    _play.hidden = YES;
    [self.contentView addSubview:_play];
    _voiceAction = [[NoshiMediaActionView alloc] initWithFrame:CGRectMake(0, 0, VOICE_BUTTON, VOICE_BUTTON)];
    _voiceAction.hidden = YES;
    [self.contentView addSubview:_voiceAction];
    _overlay = [[NoshiBubbleView alloc] init];
    _overlay.layerKind = NoshiBubbleLayerOverlay;
    [self.contentView addSubview:_overlay];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _reactions = [[NoshiReactionsView alloc] init];
    NoshiWeakReference *weak = _weak;
    _reactions.pickHandler = ^(NoshiReaction *reaction) {
        NoshiMessageCell *cell = weak.target;
        if (cell) [cell.delegate messageCell:cell didTapReaction:reaction];
    };
    _reactions.holdHandler = ^(NoshiReaction *reaction) {
        NoshiMessageCell *cell = weak.target;
        if (cell && [cell reactionTimeShown]) [cell.delegate messageCell:cell didHoldReaction:reaction];
    };
    [self.contentView addSubview:_reactions];
    UILongPressGestureRecognizer *press = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)] autorelease];
    [self.contentView addGestureRecognizer:press];
    _longPress = press;
    /* a hard press on a 3d touch screen (ios 9 and later) opens the same menu without waiting out the long press */
    _forcePress = [[[NoshiForceTouchRecognizer alloc] initWithTarget:self action:@selector(longPressed:)] autorelease];
    [self.contentView addGestureRecognizer:_forcePress];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.cancelsTouchesInView = NO;
    [tap requireGestureRecognizerToFail:press];
    [self.contentView addGestureRecognizer:tap];
    /* off while the chat has no double tap action, since a recognizer that waits for a second tap would hold every single tap back */
    _doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    _doubleTap.numberOfTapsRequired = 2;
    _doubleTap.enabled = NO;
    [self.contentView addGestureRecognizer:_doubleTap];
    [tap requireGestureRecognizerToFail:_doubleTap];
    /* the disc comes in from the right edge as the row is pulled left: a ring that fills with the pull, and a solid fill when the answer is armed */
    _swipeDisc = [[UIView alloc] initWithFrame:CGRectMake(0, 0, SWIPE_DISC, SWIPE_DISC)];
    _swipeDisc.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    _swipeDisc.layer.cornerRadius = SWIPE_DISC / 2;
    _swipeDisc.userInteractionEnabled = NO;
    _swipeDisc.alpha = 0;
    _swipeFill = [[CALayer layer] retain];
    _swipeFill.frame = _swipeDisc.bounds;
    _swipeFill.cornerRadius = SWIPE_DISC / 2;
    _swipeFill.backgroundColor = NoshiColorAccent().CGColor;
    _swipeFill.opacity = 0;
    [_swipeDisc.layer addSublayer:_swipeFill];
    _swipeRing = [[CAShapeLayer layer] retain];
    _swipeRing.frame = _swipeDisc.bounds;
    _swipeRing.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(SWIPE_DISC / 2, SWIPE_DISC / 2) radius:SWIPE_DISC / 2 - 2 startAngle:-(CGFloat)M_PI_2
                                                    endAngle:(CGFloat)(3 * M_PI_2) clockwise:YES].CGPath;
    _swipeRing.fillColor = NULL;
    _swipeRing.strokeColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    _swipeRing.lineWidth = 2;
    _swipeRing.lineCap = kCALineCapRound;
    _swipeRing.strokeEnd = 0;
    [_swipeDisc.layer addSublayer:_swipeRing];
    UIImageView *arrow = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolReply, 18, [UIColor whiteColor])] autorelease];
    arrow.center = CGPointMake(SWIPE_DISC / 2, SWIPE_DISC / 2);
    [_swipeDisc addSubview:arrow];
    [self addSubview:_swipeDisc];
    /* while messages are picked a clear cover takes every touch of the row, so no link, button or player under it answers */
    _selectCover = [[UIControl alloc] init];
    _selectCover.hidden = YES;
    [_selectCover addTarget:self action:@selector(selectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_selectCover];
    _selectMark = [[UIView alloc] initWithFrame:CGRectMake(0, 0, SELECT_MARK, SELECT_MARK)];
    _selectMark.layer.cornerRadius = SELECT_MARK / 2;
    _selectMark.layer.borderWidth = 2;
    /* a white ring is lost on the light parts of a wallpaper (the white bar of a picture of a chat is one), so the half of the circle over them read as cut off; the dark
       edge keeps the whole ring in sight on any ground */
    _selectMark.layer.shadowColor = [UIColor blackColor].CGColor;
    _selectMark.layer.shadowOpacity = 0.55f;
    _selectMark.layer.shadowRadius = 1.5f;
    _selectMark.layer.shadowOffset = CGSizeZero;
    _selectMark.userInteractionEnabled = NO;
    _selectMark.hidden = YES;
    _selectCheck = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolCheck, 14, [UIColor whiteColor])];
    _selectCheck.contentMode = UIViewContentModeCenter;
    _selectCheck.frame = _selectMark.bounds;
    [_selectMark addSubview:_selectCheck];
    [self addSubview:_selectMark];
    _swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    _swipe.delegate = self;
    _swipe.maximumNumberOfTouches = 1;
    [self.contentView addGestureRecognizer:_swipe];
    _seekPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(seekDragged:)];
    _seekPan.delegate = self;
    [self.contentView addGestureRecognizer:_seekPan];
    [_swipe requireGestureRecognizerToFail:_seekPan];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:NoshiMusicPlayerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerTicked:) name:NoshiMusicPlayerDidTickNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roundPlaybackChanged:) name:NoshiRoundPlaybackDidChangeNotification object:nil];
    return self;
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    if (_roundSpeed) [self applyRoundSpeed];
    noshi_preview_kind kind = _item.message.media.kind;
    if (kind == NOSHI_PREVIEW_AUDIO || kind == NOSHI_PREVIEW_VOICE) {
        [_body setNeedsDisplay];
        [self syncVoiceActionAnimated:YES];
    }
}

/* the bars of the note that plays fill as it goes */
- (void)playerTicked:(NSNotification *)note {
    (void)note;
    if (_item.message.media.kind == NOSHI_PREVIEW_VOICE && [[NoshiMusicPlayer sharedPlayer] isCurrentTrack:_item.message.media]) [_body setNeedsDisplay];
}

- (void)dealloc {
    /* a recognizer does not retain its target and can outlive the cell while it waits on the long press and the double tap it requires to fail, so a tap that was
       still being decided when the chat closed called tapped: on a freed cell */
    for (UIGestureRecognizer *recognizer in [NSArray arrayWithArray:self.contentView.gestureRecognizers]) [recognizer removeTarget:self action:NULL];
    [_weak clear];
    [self stopBodyGrowth];
    [self stopGif];
    [self resumeReplyTable];
    _swipe.delegate = nil;
    [_swipe release];
    _seekPan.delegate = nil;
    [_seekPan release];
    _handlePan.delegate = nil;
    [_handlePan release];
    [_swipeDisc release];
    [_swipeRing release];
    [_swipeFill release];
    [_flash release];
    [_selectCover release];
    [_selectMark release];
    [_selectCheck release];
    [_markupView release];
    [self detachRound];
    [self cancelMediaLoad];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_reactions release];
    [_reactionsKey release];
    [_albumViews release];
    [_albumMarks release];
    [_tappedMedia release];
    [_spoilerCover release];
    [_doubleTap release];
    [_commenters release];
    [_pollVoters release];
    [_share release];
    [_sharingAccept release];
    [_sharingDecline release];
    [_item release];
    [_body release];
    [_replyPreview release];
    [_overlay release];
    [_picture release];
    [_map release];
    [_gifLabel release];
    [_play release];
    [_voiceAction release];
    [_loadedPath release];
    [_giftCardView release];
    [_lottie release];
    [_slots release];
    [_pendingLottie release];
    [_pendingLottieKey release];
    [_media release];
    [_stickerLibrary release];
    [_avatar release];
    [_avatarButton release];
    [_senderButton release];
    [_avatars release];
    [super dealloc];
}

/* an emoji or sticker that can play, also before its file arrives, so the visible ones start when it does */
- (BOOL)animatedSticker {
    if (_item.message.media.kind == NOSHI_PREVIEW_GIF) return _item.content == NoshiChatItemContentPicture && _item.message.media.file && !_gifFailed && (_gifPlayRequested || [self playsOnItsOwn]) && ![self spoilerHidesItem:_item];
    return [self playsOnItsOwn] && (_item.kind == NoshiChatItemEmoji || (_item.kind == NoshiChatItemSticker &&
        (_item.message.media.stickerFormat == NOSHI_STICKER_ANIMATED || _item.message.media.stickerFormat == NOSHI_STICKER_VIDEO) && _item.message.media.file != nil));
}

/* the power saving settings decide whether stickers and the big emoji play as they come into view; when they do not, the picture stands still and a tap plays
   it once */
- (BOOL)playsOnItsOwn {
    if (_item.message.media.kind == NOSHI_PREVIEW_GIF) return !NoshiReduceMotionEnabled() && NoshiLiteEnabled(NOSHI_LITE_AUTOPLAY_GIFS);
    return NoshiLiteEnabled(_item.kind == NoshiChatItemEmoji ? NOSHI_LITE_EMOJI_CHAT : NOSHI_LITE_STICKERS_CHAT);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self clearTextSelection];
    /* the slide of a new message runs on the layer of the cell, and a cell taken for another row in the middle of it would carry the slide to that row */
    NoshiCancelEnter(self);
    [self stopBodyGrowth];
    [self hideAlbumViews];
    [self resetSwipe];
    [self stopGif];
    [self detachRound];
    [self cancelMediaLoad];
    ++_token;
    [self discardLottie];
    [_giftCardView discard];
    _giftCardView.hidden = YES;
    _animationLoading = NO;
    _animating = NO;
    _gifPlayRequested = NO;
    _gifLabel.hidden = YES;
    _picture.image = nil;
    [_map cancelTiles]; _map.hidden=YES;
    _markupView.hidden = YES;
}

/* where a photo stands while it loads: a quiet tint of the bubble it will sit in */
- (UIColor *)placeholderColor {
    return NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithWhite:0 alpha:0.06];
}

/* the files behind the picture of a row: the picture itself, and the preview that stands in while there is none;
   the cell that shows a row and the preparation ahead of it both ask here */
static void NoshiPictureSources(NoshiChatItem *item, NoshiRemoteFile **file, NoshiRemoteFile **preview) {
    NoshiMedia *content = item.message.media;
    *file = nil;
    *preview = nil;
    if (item.kind == NoshiChatItemSticker) {
        if (content.stickerFormat == NOSHI_STICKER_STATIC && content.file) *file = content.file;
        *preview = content.previewFile;
        if (!*file && !*preview) *preview = content.file;
    } else if (item.kind == NoshiChatItemRound) {
        *preview = content.previewFile;
    } else if (item.content == NoshiChatItemContentPicture) {
        if (content.kind != NOSHI_PREVIEW_PHOTO) *preview = content.previewFile;
        else *file = content.file;
    }
}

static CGFloat NoshiPictureSide(NoshiChatItem *item) {
    return MAX(item.pictureFrame.size.width, item.pictureFrame.size.height) * NoshiScreenScale();
}

+ (void)prepareItem:(NoshiChatItem *)item media:(NoshiMediaCache *)media {
    NoshiRemoteFile *file = nil;
    NoshiRemoteFile *preview = nil;
    NoshiPictureSources(item, &file, &preview);
    NoshiRemoteFile *shown = file ? file : preview;
    if (shown) [media prepareImageForFile:shown maxSide:NoshiPictureSide(item)];
}

/* a hidden picture is covered at its frame until it is tapped; an album and the other kinds of content have no such cover */
- (BOOL)spoilerHidesItem:(NoshiChatItem *)item {
    NoshiMessage *message = item.message;
    if (item.content != NoshiChatItemContentPicture || item.albumFrames.count || message.spoilersRevealed) return NO;
    NoshiOutgoing *pending = message.pendingSend;
    return message.media.spoiler || (pending && pending->spoiler);
}

- (void)refreshSpoilerCoverForItem:(NoshiChatItem *)item {
    if (![self spoilerHidesItem:item]) {
        _spoilerCover.hidden = YES;
        return;
    }
    if (!_spoilerCover) {
        _spoilerCover = [[NoshiSpoilerCover alloc] init];
        _spoilerCover.source = _picture;
    }
    _spoilerCover.frame = _picture.frame;
    _spoilerCover.layer.cornerRadius = _picture.layer.cornerRadius;
    _spoilerCover.hidden = NO;
    _spoilerCover.alpha = 1;
    [self.contentView insertSubview:_spoilerCover aboveSubview:_picture];
    [_spoilerCover setNeedsDisplay];
}

- (void)loadPictureForItem:(NoshiChatItem *)item {
    NoshiRemoteFile *file = nil;
    NoshiRemoteFile *preview = nil;
    NoshiPictureSources(item, &file, &preview);
    CGFloat side = NoshiPictureSide(item);
    NSUInteger token = _token;
    /* a photo or video on its way up shows its own small picture, so the bubble is the picture from the first moment and not a file line */
    UIImage *local = item.message.localPreview;
    if (local && !file && !preview) {
        _picture.image = local;
        [_spoilerCover setNeedsDisplay];
        _picture.backgroundColor = [UIColor clearColor];
        return;
    }
    UIImage *ready = [_media cachedImageForFile:file maxSide:side];
    if (ready) {
        _picture.image = ready;
        [_spoilerCover setNeedsDisplay];
        return;
    }
    _picture.backgroundColor = item.kind == NoshiChatItemSticker ? [UIColor clearColor] : [self placeholderColor];
    if (preview && !file) {
        [_media loadImageForFile:preview maxSide:side completion:^(UIImage *image) {
            if (token != _token) return;
            if (image) { _picture.image = image; [_spoilerCover setNeedsDisplay]; }
            else if (item.kind == NoshiChatItemSticker && preview != item.message.media.file) {
                [_media loadImageForFile:item.message.media.file maxSide:side completion:^(UIImage *poster) {
                    if (token == _token && poster) { _picture.image = poster; [_spoilerCover setNeedsDisplay]; }
                }];
            }
        }];
        return;
    }
    /* a photo that takes a moment shows the ring turning on its button; one that comes at once shows nothing, so a scroll does not flash it */
    BOOL ringed = item.content == NoshiChatItemContentPicture && item.message.media.kind == NOSHI_PREVIEW_PHOTO;
    if (ringed) [self performSelector:@selector(showPhotoLoading) withObject:nil afterDelay:0.25];
    [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
        if (token != _token) return;
        if (image) {
            _picture.image = image;
            [_spoilerCover setNeedsDisplay];
            _picture.backgroundColor = [UIColor clearColor];
        }
        if (ringed) [self photoFinished];
    }];
}

- (void)showPhotoLoading {
    if (_photoLoadShown || _picture.image) return;
    _photoLoadShown = YES;
    [self placeMediaButtonOver:_picture.frame];
    [_play setIcon:NoshiMediaIconCancel animated:NO];
    [_play setProgress:0];
}

/* the picture is in: the ring and the cross shrink away, and the button leaves when they are gone */
- (void)photoFinished {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showPhotoLoading) object:nil];
    if (!_photoLoadShown) return;
    _photoLoadShown = NO;
    [_play setIcon:NoshiMediaIconNone animated:YES];
    [self performSelector:@selector(hidePhotoLoading) withObject:nil afterDelay:0.3];
}

- (void)hidePhotoLoading {
    if (_item.kind != NoshiChatItemRound && _item.message.media.kind == NOSHI_PREVIEW_PHOTO) _play.hidden = YES;
}

- (void)loadLottieFile:(NoshiRemoteFile *)file {
    if (!file || _animationLoading || _lottie) return;
    _animationLoading = YES;
    NSUInteger token = _token;
    NSString *key = file.key;
    NoshiWeakReference *weak = _weak;
    [_media loadDataForFile:file completion:^(NSData *data) {
        NoshiMessageCell *cell = weak.target;
        if (!cell || token != cell->_token) return;
        cell->_animationLoading = NO;
        if (!data || (NoshiFileFormatOfData(data) != NoshiFileFormatGzip && NoshiFileFormatOfData(data) != NoshiFileFormatMatroska)) {
            NSLog(@"noshigram: animation %@ did not load as tgs or webm", key);
            return;
        }
        if (cell->_activationDeferred) {
            [cell->_pendingLottie release];
            cell->_pendingLottie = [data retain];
            [cell->_pendingLottieKey release];
            cell->_pendingLottieKey = [key copy];
            return;
        }
        [cell showLottieWithData:data key:key];
    }];
}

- (void)loadLottieForItem:(NoshiChatItem *)item {
    /* the thumbnail fills in until the animation has its first frame */
    [self loadPictureForItem:item];
    [self loadLottieFile:item.message.media.file];
}

/* the outline the person chose for stickers: the picture is clipped to it, and the third shape puts a plate of the bubble's color under the picture */
- (void)applyStickerShape {
    if (_item.kind != NoshiChatItemSticker) return;
    NoshiStickerShape shape = NoshiChatStickerShape();
    CGFloat radius = shape == NoshiStickerShapeNone ? 0 : (shape == NoshiStickerShapeRounded ? floor(_picture.frame.size.width * 0.12) : (CGFloat)NoshiBubbleRadius());
    UIColor *plate = shape == NoshiStickerShapeBubble ? (_item.message.outgoing ? NoshiColorBubbleOut() : NoshiColorBubbleIn()) : [UIColor clearColor];
    _picture.layer.cornerRadius = radius;
    _picture.layer.masksToBounds = YES;
    _picture.backgroundColor = plate;
    _lottie.layer.cornerRadius = radius;
    _lottie.layer.masksToBounds = YES;
    _lottie.backgroundColor = plate;
}

/* a game emoji: the set of the game holds one throw for each result, and the first of them loops while the result is not known. the slot machine is five layers, not one throw, so
   it stays the picture of its emoji */
- (void)loadDiceAnimation {
    NoshiMedia *media = _item.message.media;
    if ([media.alt isEqualToString:@"\U0001F3B0"]) {
        [self loadSlotsAnimation];
    } else {
        _animationLoading = YES;
        NSUInteger token = _token;
        NoshiWeakReference *weak = _weak;
        NSUInteger index = media.diceValue > 0 ? (NSUInteger)media.diceValue : 0;
        [_stickerLibrary loadDiceForEmoji:media.alt completion:^(NSArray *stickers, NSString *error) {
            NoshiMessageCell *cell = weak.target;
            if (!cell || token != cell->_token) return;
            cell->_animationLoading = NO;
            if (index >= stickers.count) {
                NSLog(@"noshigram: the %@ set has no throw %lu (%@)", media.alt, (unsigned long)index, error ?: @"short set");
                return;
            }
            NoshiSticker *sticker = [stickers objectAtIndex:index];
            if (sticker.media.file) [cell loadLottieFile:sticker.media.file];
        }];
    }
}

/* the five layers of the machine are five documents of the set, which the plan of the throw names, so all five are fetched before the machine is built */
- (void)loadSlotsAnimation {
    NoshiMedia *media = _item.message.media;
    int32_t result = media.diceValue;
    NSArray *indexes = [NoshiSlotsView documentIndexesForResult:result];
    if (!indexes) {
        result = 0;
        indexes = [NoshiSlotsView documentIndexesForResult:0];
    }
    _animationLoading = YES;
    NSUInteger token = _token;
    NoshiWeakReference *weak = _weak;
    [_stickerLibrary loadDiceForEmoji:media.alt completion:^(NSArray *stickers, NSString *error) {
        NoshiMessageCell *cell = weak.target;
        if (!cell || token != cell->_token) return;
        NSMutableArray *files = [NSMutableArray arrayWithCapacity:indexes.count];
        for (NSNumber *index in indexes) {
            NSUInteger at = index.unsignedIntegerValue;
            NoshiSticker *sticker = at < stickers.count ? [stickers objectAtIndex:at] : nil;
            if (!sticker.media.file) {
                NSLog(@"noshigram: the slot machine lacks its document %lu (%@)", (unsigned long)at, error ?: @"short set");
                cell->_animationLoading = NO;
                return;
            }
            [files addObject:sticker.media.file];
        }
        __block NSUInteger waiting = files.count;
        NSMutableArray *data = [NSMutableArray arrayWithCapacity:files.count];
        for (NSUInteger i = 0; i < files.count; ++i) [data addObject:[NSNull null]];
        for (NSUInteger i = 0; i < files.count; ++i) {
            [cell->_media loadDataForFile:[files objectAtIndex:i] completion:^(NSData *bytes) {
                NoshiMessageCell *again = weak.target;
                if (!again || token != again->_token) return;
                if (bytes) [data replaceObjectAtIndex:i withObject:bytes];
                if (--waiting) return;
                again->_animationLoading = NO;
                for (id item in data) {
                    if (![item isKindOfClass:[NSData class]]) {
                        NSLog(@"noshigram: a layer of the slot machine did not load");
                        return;
                    }
                }
                [again showSlotsWithData:data result:result];
            }];
        }
    }];
}

- (void)showSlotsWithData:(NSArray *)data result:(int32_t)result {
    if (_slots || _lottie) return;
    NoshiSlotsView *slots = [[NoshiSlotsView alloc] initWithLayers:data result:result keyBase:@"slots"];
    if (!slots) return;
    _slots = slots;
    NSUInteger token = _token;
    NoshiWeakReference *weak = _weak;
    slots.firstFrameHandler = ^{
        NoshiMessageCell *cell = weak.target;
        if (cell && token == cell->_token) cell->_picture.hidden = YES;
    };
    slots.frame = _picture.frame;
    [self.contentView insertSubview:slots aboveSubview:_picture];
    if (_replayRequested) {
        _replayRequested = NO;
        _emojiPlayed = YES;
        [self replayAnimation];
    } else [self setAnimating:_animating];
}

- (void)loadEmojiAnimation {
    if (!_stickerLibrary || _animationLoading || _lottie || _slots) return;
    if (_item.message.media.kind == NOSHI_PREVIEW_DICE) {
        [self loadDiceAnimation];
        return;
    }
    _animationLoading = YES;
    NSUInteger token = _token;
    NoshiWeakReference *weak = _weak;
    [_stickerLibrary loadAnimationForEmoji:_item.message.text completion:^(NoshiSticker *sticker, NSString *error) {
        (void)error;
        NoshiMessageCell *cell = weak.target;
        if (!cell || token != cell->_token) return;
        cell->_animationLoading = NO;
        if (sticker) [cell loadLottieFile:sticker.media.file];
    }];
}

/* parsing the animation and building its renderer is the heaviest step of a sticker row, so it waits out a scroll */
- (void)showLottieWithData:(NSData *)data key:(NSString *)key {
    if (_lottie) return;
    if (NoshiFileFormatOfData(data) == NoshiFileFormatMatroska && !_animating) {
        [_pendingLottie release]; _pendingLottie = [data retain];
        [_pendingLottieKey release]; _pendingLottieKey = [key copy];
        return;
    }
    _lottie = [[NoshiLottieView alloc] initWithPackedData:data key:key];
    NSUInteger token = _token;
    NoshiWeakReference *weak = _weak;
    _lottie.firstFrameHandler = ^{
        NoshiMessageCell *cell = weak.target;
        if (cell && token == cell->_token) cell->_picture.hidden = YES;
    };
    _lottie.frame = _picture.frame;
    [_lottie setLoaded:YES];
    [self.contentView insertSubview:_lottie aboveSubview:_picture];
    [self applyStickerShape];
    if (_replayRequested) {
        _replayRequested = NO;
        _emojiPlayed = YES;
        [self replayAnimation];
    } else [self setAnimating:_animating];
}

- (BOOL)activationDeferred {
    return _activationDeferred;
}

- (void)setActivationDeferred:(BOOL)deferred {
    _activationDeferred = deferred;
    if (!deferred && _animating && _item.message.media.kind == NOSHI_PREVIEW_GIF) [self startGif];
    if (deferred || !_pendingLottie) return;
    NSData *data = [_pendingLottie autorelease];
    NSString *key = [_pendingLottieKey autorelease];
    _pendingLottie = nil;
    _pendingLottieKey = nil;
    [self showLottieWithData:data key:key];
}

- (void)discardLottie {
    [_pendingLottie release];
    _pendingLottie = nil;
    [_pendingLottieKey release];
    _pendingLottieKey = nil;
    [_lottie removeFromSuperview];
    [_lottie setPlaying:NO];
    [_lottie release];
    _lottie = nil;
    [_slots removeFromSuperview];
    [_slots setActive:NO];
    [_slots release];
    _slots = nil;
}

/* the sender's picture stands at the left edge, level with the bottom of the last bubble of a run */
- (void)configureAvatarForItem:(NoshiChatItem *)item bubble:(CGRect)bubble {
    _senderButton.hidden = !item.senderPerson || !item.senderName.length || !item.senderLayout;
    _senderButton.frame = CGRectMake(bubble.origin.x + item.senderOrigin.x, bubble.origin.y + item.senderOrigin.y - 3,
        item.senderLayout.size.width, 23);
    _senderButton.accessibilityLabel = item.senderName;
    _avatarButton.hidden = !item.showsAvatar || !item.senderPerson;
    _avatarButton.accessibilityLabel = item.senderName;
    if (!item.showsAvatar || item.kind == NoshiChatItemPill) {
        _avatar.hidden = YES;
        return;
    }
    NoshiPerson *person = item.senderPerson;
    _avatar.hidden = NO;
    _avatar.frame = CGRectMake(8, CGRectGetMaxY(bubble) - 34, 34, 34);
    _avatarButton.frame = CGRectInset(_avatar.frame, -4, -4);
    _avatar.seed = (NSUInteger)(llabs(item.message.senderKey) % 1000003);
    _avatar.initials = person.initials;
    _avatar.deleted = person.deleted;
    [_avatar setPhoto:person.photo cache:_avatars];
}

- (void)senderTapped:(UIControl *)control event:(UIEvent *)event {
    [_delegate messageCellDidTapSender:self];
}

/* the pictures of the last voters of a public poll stand before the count of votes, in views made when the first such poll needs them */
- (void)configurePollVotersForItem:(NoshiChatItem *)item bubble:(CGRect)bubble {
    NSUInteger shown = item.content == NoshiChatItemContentPoll ? MIN(item.pollVoterPeople.count, (NSUInteger)3) : 0;
    if (shown && !_pollVoters) {
        _pollVoters = [[NSMutableArray alloc] init];
        for (int i = 0; i < 3; ++i) {
            NoshiAvatarView *view = [[[NoshiAvatarView alloc] init] autorelease];
            [self.contentView addSubview:view];
            [_pollVoters addObject:view];
        }
    }
    CGFloat footerY = item.pollFooterOwnRow ? item.pollFooterY : item.timeOrigin.y;
    for (NSUInteger i = 0; i < _pollVoters.count; ++i) {
        NoshiAvatarView *view = [_pollVoters objectAtIndex:i];
        view.hidden = i >= shown;
        if (i >= shown) continue;
        NoshiPerson *person = [item.pollVoterPeople objectAtIndex:i];
        view.frame = CGRectMake(bubble.origin.x + PAD_X_POLL + (CGFloat)i * NOSHI_POLL_VOTER_STEP,
                                bubble.origin.y + footerY + (META_HEIGHT_POLL - NOSHI_POLL_VOTER_SIDE) / 2, NOSHI_POLL_VOTER_SIDE, NOSHI_POLL_VOTER_SIDE);
        view.seed = (NSUInteger)(person.userId % 1000003);
        view.initials = person.initials;
        view.deleted = person.deleted;
        [view setPhoto:person.photo cache:_avatars];
    }
}

/* what a channel post adds around its bubble: the pictures of the newest commenters on its comments row, and the
   round share button on the right */
- (void)configurePostExtrasForItem:(NoshiChatItem *)item bubble:(CGRect)bubble {
    NSUInteger shown = item.commentsText.length ? MIN(item.commenterPeople.count, (NSUInteger)3) : 0;
    if (shown && !_commenters) {
        _commenters = [[NSMutableArray alloc] init];
        for (int i = 0; i < 3; ++i) {
            NoshiAvatarView *view = [[[NoshiAvatarView alloc] init] autorelease];
            [self.contentView addSubview:view];
            [_commenters addObject:view];
        }
    }
    for (NSUInteger i = 0; i < _commenters.count; ++i) {
        NoshiAvatarView *view = [_commenters objectAtIndex:i];
        view.hidden = i >= shown;
        if (i >= shown) continue;
        NoshiPerson *person = [item.commenterPeople objectAtIndex:i];
        CGRect row = item.commentsFrame;
        view.frame = CGRectMake(bubble.origin.x + row.origin.x + PAD_X_COMMENTS + (CGFloat)i * COMMENTER_STEP,
                                bubble.origin.y + row.origin.y + (row.size.height - COMMENTER_SIDE) / 2, COMMENTER_SIDE, COMMENTER_SIDE);
        view.seed = (NSUInteger)(person.userId % 1000003);
        view.initials = person.initials;
        view.deleted = person.deleted;
        [view setPhoto:person.photo cache:_avatars];
    }
    if (item.showsShare && !_share) {
        _share = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _share.backgroundColor = NoshiColorBubbleCapsule();
        _share.layer.cornerRadius = 16;
        [_share setImage:NoshiSymbolImage(NoshiSymbolShare, 16, [UIColor whiteColor]) forState:UIControlStateNormal];
        [_share addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_share];
    }
    _share.hidden = !item.showsShare;
    if (item.showsShare) _share.frame = CGRectOffset(item.shareFrame, bubble.origin.x, bubble.origin.y);
}

/* the keyboard under a bot's message is a view made when the first such row needs it, hidden for every other row */
- (void)configureMarkupForItem:(NoshiChatItem *)item {
    if (!item.markup) {
        _markupView.hidden = YES;
        return;
    }
    if (!_markupView) {
        _markupView = [[NoshiMarkupView alloc] init];
        NoshiWeakReference *weak = _weak;
        _markupView.pressHandler = ^(NoshiMarkupButton *button) {
            NoshiMessageCell *cell = weak.target;
            if (cell) [cell.delegate messageCell:cell didPressButton:button];
        };
        [self.contentView addSubview:_markupView];
    }
    _markupView.hidden = NO;
    _markupView.frame = item.markupFrame;
    [_markupView setMarkup:item.markup frames:item.markupButtons];
}

- (void)setBusyMarkupButton:(NoshiMarkupButton *)button {
    [_markupView setBusyButton:button];
}

- (CGFloat)bodyHeight {
    return _body.frame.size.height;
}

- (void)setBodyHeight:(CGFloat)height {
    CGRect frame = _body.frame, bounds = _body.bounds;
    frame.size.height = height;
    bounds.size.height = height;
    _body.frame = frame;
    _body.bounds = bounds;
    [_body setNeedsDisplay];
}

- (void)stopBodyGrowth {
    if (!_growLink) return;
    [_growLink invalidate];
    _growLink = nil;
}

/* a reaction row makes the bubble taller by the height of the chips; the table moves the rows under it, and the bubble follows on the same 250 ms */
- (void)growBodyFromHeight:(CGFloat)from {
    CGFloat to = _body.frame.size.height;
    if (NoshiReduceMotionEnabled() || _item.kind != NoshiChatItemBubble || from <= 0 || fabs(from - to) < 1) return;
    [self stopBodyGrowth];
    _growFrom = from;
    _growTo = to;
    _growStart = CACurrentMediaTime();
    [self setBodyHeight:from];
    NoshiBodyGrowTicker *ticker = [[[NoshiBodyGrowTicker alloc] initWithTarget:self] autorelease];
    _growLink = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
    [_growLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)growBodyStep:(CADisplayLink *)link {
    (void)link;
    CGFloat t = (CGFloat)MIN(1.0, (CACurrentMediaTime() - _growStart) / BODY_GROW_SECONDS);
    CGFloat eased = 1 - (1 - t) * (1 - t) * (1 - t);
    [self setBodyHeight:_growFrom + (_growTo - _growFrom) * eased];
    if (t >= 1) [self stopBodyGrowth];
}

- (void)configureWithItem:(NoshiChatItem *)item media:(NoshiMediaCache *)media avatars:(NoshiAvatarCache *)avatars {
    [self resetSwipe];
    if (_pick.length && (!_item || ![_item isSameRowAs:item] || item.textLayout != _item.textLayout)) [self clearTextSelection];
    [self stopBodyGrowth];
    BOOL sameFile = _item && [_item isSameRowAs:item] && _item.message.media.kind == item.message.media.kind &&
        [_item.message.media.file.key isEqualToString:item.message.media.file.key];
    BOOL keepMedia = sameFile && (_loadRequest || _loadedPath || _gifPlayer || _lottie);
    BOOL played = _item && [_item isSameRowAs:item] && _emojiPlayed;
    if (!keepMedia) {
        ++_token;
        [self stopGif];
        [self detachRound];
        [self cancelMediaLoad];
        [self discardLottie];
        _gifFailed = NO;
        _gifPlayRequested = NO;
        _animationLoading = NO;
        _animating = NO;
    }
    if (_roundView) _play.transform = CGAffineTransformIdentity;
    _emojiPlayed = played;
    _replayRequested = NO;
    [item retain];
    [_item release];
    _item = item;
    /* a kept message the other side deleted is faded, if the person likes it so */
    self.contentView.alpha = 1.0f;
    _body.alpha = 1;
    [_flash.layer removeAllAnimations];
    _flash.alpha = 0;
    [_media release];
    _media = [media retain];
    [_avatars release];
    _avatars = [avatars retain];
    CGRect bubble = item.bubbleFrame;
    [self configureAvatarForItem:item bubble:bubble];
    _body.item = item;
    _replyPreview.item = item;
    _replyPreview.hidden = item.kind == NoshiChatItemBubble || CGRectIsEmpty(item.replyFrame);
    _replyPreview.frame = CGRectOffset(item.replyFrame, bubble.origin.x, bubble.origin.y);
    [_replyPreview setNeedsDisplay];
    /* a classic bubble ends its run with a tail, which takes a few points beside it. a picture without words is a frame around the picture, and a tail on it points at nothing */
    BOOL pictureAlone = item.content == NoshiChatItemContentPicture && !item.textLayout;
    CGFloat tail = item.kind == NoshiChatItemBubble && !item.bare && !pictureAlone && !item.joinsNext && !NoshiChatFlagGet(NoshiChatFlagRemoveTail) ? NOSHI_CLASSIC_BUBBLE_TAIL : 0;
    _body.tailWidth = tail;
    CGRect bodyFrame = bubble;
    if (item.kind != NoshiChatItemBubble && !CGRectIsEmpty(item.commentsFrame)) {
        bodyFrame.origin.x += MIN(0, item.commentsFrame.origin.x);
        bodyFrame.size.width = MAX(CGRectGetMaxX(bubble), bubble.origin.x + CGRectGetMaxX(item.commentsFrame)) - bodyFrame.origin.x;
        bodyFrame.size.height = CGRectGetMaxY(item.commentsFrame);
    }
    bodyFrame.size.width += tail;
    if (!item.message.outgoing) bodyFrame.origin.x -= tail;
    _body.frame = bodyFrame;
    _body.bounds = CGRectMake(bodyFrame.origin.x - bubble.origin.x + (!item.message.outgoing ? tail : 0), 0, bodyFrame.size.width, bodyFrame.size.height);
    [_body setNeedsDisplay];
    _picture.hidden = YES;
    _map.hidden = YES;
    if (item.message.media.kind != NOSHI_PREVIEW_LOCATION) [_map cancelTiles];
    _gifLabel.hidden = YES;
    _spoilerCover.hidden = YES;
    [self hideAlbumViews];
    if (!keepMedia) _picture.image = nil;
    _picture.layer.cornerRadius = 0;
    _picture.layer.mask = nil;
    _play.hidden = YES;
    _voiceAction.hidden = YES;
    _overlay.hidden = YES;
    _doubleTap.enabled = item.message && item.kind != NoshiChatItemPill && item.message.messageId > 0 && NoshiChatDoubleTap(item.message.outgoing) != NoshiDoubleTapNone;
    _reactions.avatars = avatars;
    /* a chip pops in only when this same message got a reaction while it was on screen, not when a reused row is filled with another message */
    NSString *reactionKey = [item.message.reactionKey copy];
    BOOL reactionsChanged = _reactionsMessageId == item.message.messageId && item.message.messageId > 0 && _reactionsKey && ![_reactionsKey isEqualToString:reactionKey ? reactionKey : @""];
    [_reactionsKey release];
    _reactionsKey = [(reactionKey ? reactionKey : @"") copy];
    _reactionsMessageId = item.message.messageId;
    [reactionKey release];
    _reactions.inBubble = item.reactionsInside;
    _reactions.outgoing = item.message.outgoing;
    [_reactions setReactions:[item shownReactions] counts:YES animated:reactionsChanged];
    _reactions.alignRight = item.message.outgoing && !item.reactionsInside && !item.giftCard;
    /* the last chip of a message shrinks where it stood, and the frame of an empty row would take it to the corner */
    if ([item shownReactions].count || !_reactions.animatingOut) _reactions.frame = item.reactionFrame;
    _reactions.hidden = ![item shownReactions].count && !_reactions.animatingOut;
    [self configureMarkupForItem:item];
    [self configurePostExtrasForItem:item bubble:bubble];
    [self configurePollVotersForItem:item bubble:bubble];
    if (item.giftCard) {
        if (!_giftCardView) {
            _giftCardView = [[NoshiGiftCardView alloc] init];
            [self.contentView addSubview:_giftCardView];
        }
        _giftCardView.hidden = NO;
        _giftCardView.frame = item.bubbleFrame;
        [_giftCardView configureWithLayout:item.giftCard media:media];
        [_giftCardView setActive:_animating];
    } else _giftCardView.hidden = YES;
    BOOL sharingOffer = item.message.service == NOSHI_SERVICE_SHARING_REQUEST + 1 && !item.message.outgoing && !item.sharingExpired && item.message.messageId > 0;
    if (sharingOffer && !_sharingAccept) {
        _sharingAccept = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _sharingDecline = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        for (UIButton *button in [NSArray arrayWithObjects:_sharingDecline, _sharingAccept, nil]) {
            button.titleLabel.font = NoshiFontMedium(13);
            button.backgroundColor = NoshiColorAccent();
            button.layer.cornerRadius = 8;
            [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [self.contentView addSubview:button];
        }
        [_sharingAccept setTitle:NSLocalizedString(@"chat.sharing.accept", nil) forState:UIControlStateNormal];
        [_sharingDecline setTitle:NSLocalizedString(@"chat.sharing.decline", nil) forState:UIControlStateNormal];
        [_sharingAccept addTarget:self action:@selector(acceptSharing) forControlEvents:UIControlEventTouchUpInside];
        [_sharingDecline addTarget:self action:@selector(declineSharing) forControlEvents:UIControlEventTouchUpInside];
    }
    _sharingAccept.hidden = !sharingOffer;
    _sharingDecline.hidden = !sharingOffer;
    if (sharingOffer) {
        CGFloat width = MIN(260, self.contentView.bounds.size.width - 24);
        CGFloat x = floor((self.contentView.bounds.size.width - width) / 2);
        _sharingDecline.frame = CGRectMake(x, CGRectGetMaxY(bubble) + 4, (width - 4) / 2, 36);
        _sharingAccept.frame = CGRectMake(x + (width + 4) / 2, CGRectGetMaxY(bubble) + 4, (width - 4) / 2, 36);
    }
    if (item.kind == NoshiChatItemPill) return;
    NoshiMedia *content = item.message.media;
    BOOL pictureOnly = (item.content == NoshiChatItemContentPicture && (!item.textLayout || item.captionAbove)) || item.bare;
    if (item.kind == NoshiChatItemEmoji) {
        _picture.hidden = _lottie.layer.contents != nil;
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.backgroundColor = [UIColor clearColor];
        _picture.image = NoshiEmojiImageNow(item.singleEmoji);
        NSUInteger token = _token;
        NoshiWeakReference *weak = _weak;
        NoshiLargeEmojiImage(item.singleEmoji, ^(UIImage *image) {
            NoshiMessageCell *cell = weak.target;
            if (cell && token == cell->_token && image) cell->_picture.image = image;
        });
        if ([self playsOnItsOwn]) [self loadEmojiAnimation];
        pictureOnly = YES;
    } else if (item.kind == NoshiChatItemSticker) {
        _picture.hidden = _lottie.layer.contents != nil;
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.backgroundColor = [UIColor clearColor];
        if ((content.stickerFormat == NOSHI_STICKER_ANIMATED || content.stickerFormat == NOSHI_STICKER_VIDEO) && content.file && [self playsOnItsOwn]) [self loadLottieForItem:item];
        else [self loadPictureForItem:item];
        [self applyStickerShape];
        pictureOnly = YES;
    } else if (item.kind == NoshiChatItemRound) {
        _picture.hidden = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFill;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.layer.cornerRadius = item.pictureFrame.size.width / 2;
        [self loadPictureForItem:item];
        [self placeMediaButtonOver:_picture.frame];
        /* a round message starts to come as soon as it is on screen, with the ring turning on its button */
        [self prepareMediaButtonLoading:YES];
        pictureOnly = YES;
    } else if (item.albumFrames.count) {
        [self showAlbumForItem:item bubble:bubble];
    } else if (item.content == NoshiChatItemContentPicture && content.kind == NOSHI_PREVIEW_LOCATION) {
        if (!_map) {
            _map=[[NoshiMapView alloc] initWithFrame:CGRectZero]; _map.compact=YES; _map.userInteractionEnabled=NO;
            [self.contentView insertSubview:_map belowSubview:_overlay];
        }
        _map.hidden=NO;
        _map.frame=CGRectOffset(item.pictureFrame,bubble.origin.x,bubble.origin.y);
        _map.layer.cornerRadius=NoshiBubbleRadius();
        [_map showLocation:content.location zoom:15];
        _picture.frame=_map.frame;
    } else if (item.content == NoshiChatItemContentPicture) {
        _picture.hidden = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFill;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        /* the picture runs to the edge of the bubble, so its outer corners are the bubble's; where a caption, a reply or a name meets it the corner is small, as in the other clients */
        CGFloat bubbleRadius = NoshiBubbleRadius(), nearRadius = MIN(4, bubbleRadius);
        BOOL captionBelow = item.textLayout.length > 0 && !item.captionAbove, lineAbove = item.pictureFrame.origin.y > 0.5;
        if (captionBelow || lineAbove) {
            _picture.layer.cornerRadius = 0;
            NoshiMaskCorners(_picture, _picture.frame.size, lineAbove ? nearRadius : bubbleRadius, lineAbove ? nearRadius : bubbleRadius,
                               captionBelow ? nearRadius : bubbleRadius, captionBelow ? nearRadius : bubbleRadius);
        } else {
            _picture.layer.mask = nil;
            _picture.layer.cornerRadius = bubbleRadius;
        }
        BOOL video = content.kind != NOSHI_PREVIEW_PHOTO;
        [self loadPictureForItem:item];
        if (video || [self uploading]) {
            [self placeMediaButtonOver:_picture.frame];
            /* a video waits for a tap, which brings it and shows the ring; the arrow says it is not here */
            [self prepareMediaButtonLoading:content.kind == NOSHI_PREVIEW_GIF];
        }
    }
    _gifView.frame = _picture.frame;
    if (_gifView) NoshiMirrorCorners(_gifView, _picture);
    if (content.kind == NOSHI_PREVIEW_GIF && item.content == NoshiChatItemContentPicture && !item.albumFrames.count) {
        if (!_gifLabel) {
            _gifLabel = [[UILabel alloc] init];
            _gifLabel.text = @"GIF";
            _gifLabel.font = NoshiFontMedium(12);
            _gifLabel.textColor = [UIColor whiteColor];
            _gifLabel.textAlignment = NoshiTextAlignmentCenter;
            _gifLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
            _gifLabel.layer.cornerRadius = 10;
            _gifLabel.clipsToBounds = YES;
            _gifLabel.userInteractionEnabled = NO;
            [self.contentView insertSubview:_gifLabel aboveSubview:_overlay];
        }
        _gifLabel.frame = CGRectMake(_picture.frame.origin.x + 6, _picture.frame.origin.y + 6, 36, 20);
        _gifLabel.hidden = NO;
    }
    _lottie.frame = _picture.frame;
    if (_roundView) {
        NoshiRoundPlayback *playback = [NoshiRoundPlayback sharedPlayback];
        [_play setIcon:playback.playing ? NoshiMediaIconNone : NoshiMediaIconPlay animated:NO];
        [self growRoundAnimated:NO];
    } else {
        [self adoptRound];
    }
    if (_gifPlayer && _gifItem.status == AVPlayerItemStatusReadyToPlay) _play.hidden = YES;
    [self refreshSpoilerCoverForItem:item];
    [self prepareVoiceActionForItem:item bubble:bubble];
    if (pictureOnly && !(item.kind == NoshiChatItemSticker && NoshiChatFlagGet(NoshiChatFlagHideStickerTime))) {
        _overlay.hidden = NO;
        _overlay.item = item;
        _overlay.frame = CGRectMake(bubble.origin.x + item.timeOrigin.x, bubble.origin.y + item.timeOrigin.y, item.timeSize.width, item.timeSize.height);
        [_overlay setNeedsDisplay];
    }
}

#pragma mark album

- (NoshiMessage *)tappedMediaMessage {
    return _tappedMedia ? _tappedMedia : _item.message;
}

- (void)hideAlbumViews {
    for (UIView *view in _albumViews) view.hidden = YES;
    for (UIView *view in _albumMarks) view.hidden = YES;
}

/* the picture of a video in an album is its thumbnail, and of a photo the photo; each is its own view cut to its cell of the collage */
- (void)showAlbumForItem:(NoshiChatItem *)item bubble:(CGRect)bubble {
    if (!_albumViews) {
        _albumViews = [[NSMutableArray alloc] init];
        _albumMarks = [[NSMutableArray alloc] init];
    }
    NSUInteger token = _token;
    CGFloat radius = NoshiBubbleRadius();
    /* a list that holds only some of an album (the pinned messages, a search) gives frames and messages of different counts, and each view needs both */
    NSUInteger shown = MIN(item.albumFrames.count, item.albumMessages.count);
    CGFloat near = MIN(4, radius);
    CGFloat bubbleLeft = CGFLOAT_MAX, bubbleRight = 0, collageTop = CGFLOAT_MAX, collageBottom = 0;
    for (NSUInteger i = 0; i < shown; ++i) {
        CGRect box = CGRectOffset([[item.albumFrames objectAtIndex:i] CGRectValue], bubble.origin.x, bubble.origin.y);
        bubbleLeft = MIN(bubbleLeft, box.origin.x);
        bubbleRight = MAX(bubbleRight, CGRectGetMaxX(box));
        collageTop = MIN(collageTop, box.origin.y);
        collageBottom = MAX(collageBottom, CGRectGetMaxY(box));
    }
    BOOL captioned = (item.textLayout.length > 0 && !item.captionAbove) || item.content == NoshiChatItemContentFile;
    for (NSUInteger i = 0; i < shown; ++i) {
        while (_albumViews.count <= i) {
            UIImageView *view = [[[UIImageView alloc] init] autorelease];
            view.contentMode = UIViewContentModeScaleAspectFill;
            view.clipsToBounds = YES;
            [self.contentView insertSubview:view aboveSubview:_picture];
            [_albumViews addObject:view];
            UIImageView *mark = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolPlay, 26, [UIColor whiteColor])] autorelease];
            mark.contentMode = UIViewContentModeCenter;
            [self.contentView insertSubview:mark aboveSubview:view];
            [_albumMarks addObject:mark];
        }
        UIImageView *view = [_albumViews objectAtIndex:i], *mark = [_albumMarks objectAtIndex:i];
        NoshiMessage *message = [item.albumMessages objectAtIndex:i];
        CGRect frame = CGRectOffset([[item.albumFrames objectAtIndex:i] CGRectValue], bubble.origin.x, bubble.origin.y);
        view.frame = frame;
        view.hidden = NO;
        view.image = nil;
        view.backgroundColor = [self placeholderColor];
        view.layer.cornerRadius = 0;
        mark.frame = frame;
        mark.hidden = message.media.kind == NOSHI_PREVIEW_PHOTO;
        /* the outer corners of the collage follow the bubble and the corners that meet another picture are small, as in the other clients; a caption under the collage
           makes the bottom corners small too, since the bubble goes on below them */
        BOOL left = frame.origin.x <= bubbleLeft + 0.5, right = CGRectGetMaxX(frame) >= bubbleRight - 0.5;
        BOOL top = frame.origin.y <= collageTop + 0.5, bottom = CGRectGetMaxY(frame) >= collageBottom - 0.5 && !captioned;
        CGFloat topRadius = item.pictureFrame.origin.y > 0.5 ? near : radius;
        NoshiMaskCorners(view, frame.size, top && left ? topRadius : near, top && right ? topRadius : near, bottom && right ? radius : near, bottom && left ? radius : near);
        NoshiMedia *media = message.media;
        NoshiRemoteFile *file = media.kind == NOSHI_PREVIEW_PHOTO ? media.file : media.previewFile;
        UIImage *local = message.localPreview;
        CGFloat side = frame.size.width * NoshiScreenScale();
        if (local && !file) {
            view.image = local;
            view.backgroundColor = [UIColor clearColor];
            continue;
        }
        if (!file) continue;
        UIImage *ready = [_media cachedImageForFile:file maxSide:side];
        if (ready) {
            view.image = ready;
            view.backgroundColor = [UIColor clearColor];
            continue;
        }
        [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
            if (token != _token || !image) return;
            view.image = image;
            view.backgroundColor = [UIColor clearColor];
        }];
    }
    for (NSUInteger i = shown; i < _albumViews.count; ++i) {
        [[_albumViews objectAtIndex:i] setHidden:YES];
        [[_albumMarks objectAtIndex:i] setHidden:YES];
    }
}

#pragma mark media button

/* the button sits in the middle of the picture, on the dark capsule of the bubbles */
- (void)placeMediaButtonOver:(CGRect)frame {
    _play.frame = CGRectMake(CGRectGetMidX(frame) - MEDIA_BUTTON / 2, CGRectGetMidY(frame) - MEDIA_BUTTON / 2, MEDIA_BUTTON, MEDIA_BUTTON);
    _play.discColor = NoshiColorBubbleCapsule();
    _play.hidden = NO;
}

/* the action that stands for the file of this row: the voice button of a note, the media button of the rest */
- (NoshiMediaActionView *)loadAction {
    noshi_preview_kind kind = _item.message.media.kind;
    return kind == NOSHI_PREVIEW_VOICE || kind == NOSHI_PREVIEW_AUDIO || kind == NOSHI_PREVIEW_FILE ? _voiceAction : _play;
}

/* a photo, video or document of ours that is still going up: its button is a cross with the ring of the upload, not the arrow of a file to fetch */
- (BOOL)uploading {
    NoshiMessage *message = _item.message;
    NoshiOutgoing *pending = message.pendingSend;
    return message.outgoing && message.state == NoshiMessageStateSending && pending &&
           (pending->kind == NoshiOutgoingPhoto || pending->kind == NoshiOutgoingVideo || pending->kind == NoshiOutgoingFile);
}

- (void)showUploadProgress {
    if ([self uploading]) [[self loadAction] setProgress:_item.message.uploadProgress];
}

/* the card burns: sparks over it while it fades, and the owner rebuilds the row as an expired one when the animation is over */
- (void)playBurnWithCompletion:(void (^)(void))completion {
    if (!NoshiMessageIsViewOnce(_item.message) || _item.content != NoshiChatItemContentFile) {
        if (completion) completion();
        return;
    }
    CGRect card = [self.contentView convertRect:CGRectInset(_item.fileFrame, -6, -4) fromView:_body];
    [UIView animateWithDuration:0.8 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{ _body.alpha = 0.25f; } completion:nil];
    [NoshiBurnEffect burnRect:card inView:self.contentView duration:0.9 completion:completion];
}

- (void)flashHighlight {
    if (!_flash) {
        _flash = [[UIView alloc] init];
        _flash.userInteractionEnabled = NO;
        [self.contentView insertSubview:_flash atIndex:0];
    }
    _flash.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:NoshiThemeIsDark() ? 0.26f : 0.2f];
    CGRect bubble = _item.bubbleFrame;
    CGFloat top = MAX(0, CGRectGetMinY(bubble));
    CGFloat bottom = MIN(self.contentView.bounds.size.height, CGRectGetMaxY(bubble));
    _flash.frame = CGRectMake(0, top, self.contentView.bounds.size.width, MAX(0, bottom - top));
    [_flash.layer removeAllAnimations];
    _flash.alpha = 0;
    UIView *flash = _flash;
    [UIView animateWithDuration:0.14 animations:^{ flash.alpha = 1; } completion:^(BOOL finished) {
        if (!finished) return;
        [UIView animateWithDuration:0.7 delay:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{ flash.alpha = 0; } completion:nil];
    }];
}

- (void)cancelSending {
    if ([_delegate respondsToSelector:@selector(messageCellDidCancelSending:)]) [_delegate messageCellDidCancelSending:self];
}

/* the glyph a file shows before anything is asked of it: the triangle when it is on the disk, the ring when it is
   coming, the arrow when it has to be asked for */
- (void)prepareMediaButtonLoading:(BOOL)startAtOnce {
    NoshiMedia *content = _item.message.media;
    if ([self uploading]) {
        [[self loadAction] setIcon:NoshiMediaIconCancel animated:NO];
        [[self loadAction] setProgress:_item.message.uploadProgress];
        return;
    }
    if (_loadRequest) {
        [[self loadAction] setIcon:NoshiMediaIconCancel animated:NO];
        [[self loadAction] setProgress:_loadProgress];
        [self showFileProgress:_loadProgress];
        return;
    }
    NSString *path = _loadedPath ? _loadedPath : [_media cachedPathForFile:content.file size:content.size];
    if (path) {
        if (!_loadedPath) _loadedPath = [path copy];
        [[self loadAction] setIcon:NoshiMediaIconPlay animated:NO];
        return;
    }
    [[self loadAction] setIcon:NoshiMediaIconDownload animated:NO];
    if (startAtOnce) [self startMediaLoad:NO];
}

- (void)startMediaLoad:(BOOL)asked {
    NoshiMedia *content = _item.message.media;
    if (_loadRequest || _loadedPath || !content.file) return;
    NoshiMediaActionView *action = [self loadAction];
    /* a tap asks again for a file that did not come, without waiting out the pause the cache keeps after a failure */
    if (_loadFailed) [_media retryFile:content.file];
    _loadFailed = NO;
    _loadAsked = asked;
    [action setIcon:NoshiMediaIconCancel animated:YES];
    _loadProgress = 0;
    [action setProgress:0];
    [self showFileProgress:0];
    NSUInteger token = ++_loadToken;
    NoshiWeakReference *weak = _weak;
    NSUInteger request = [_media loadPathForFile:content.file size:content.size progress:^(float fraction) {
        NoshiMessageCell *cell = weak.target;
        if (cell && token == cell->_loadToken) {
            cell->_loadProgress = fraction;
            [[cell loadAction] setProgress:fraction];
            [cell showFileProgress:fraction];
        }
    } completion:^(NSString *path) {
        NoshiMessageCell *cell = weak.target;
        if (!cell || token != cell->_loadToken) return;
        cell->_loadRequest = 0;
        if (!path) {
            NSLog(@"noshigram: media %@ did not arrive", content.file.key);
            cell->_loadFailed = YES;
            cell->_playWhenLoaded = NO;
            cell->_body.fileProgressText = nil;
            [cell->_body setNeedsDisplay];
            [[cell loadAction] setIcon:NoshiMediaIconDownload animated:YES];
            if (cell->_loadAsked && cell.window) NoshiShowNotice(nil, NSLocalizedString(@"media.failed", nil));
            return;
        }
        [cell->_loadedPath release];
        cell->_loadedPath = [path copy];
        [cell mediaArrived];
        if (cell->_loadAsked && [cell.delegate respondsToSelector:@selector(messageCell:didDownloadMedia:)]) [cell.delegate messageCell:cell didDownloadMedia:cell->_item.message];
    }];
    if (request && token == _loadToken && !_loadedPath && !_loadFailed) _loadRequest = request;
}

/* the file is on the disk: the ring turns into the triangle, and a round message that was asked to play does */
- (void)mediaArrived {
    _body.fileProgressText = nil;
    [_body setNeedsDisplay];
    noshi_preview_kind kind = _item.message.media.kind;
    if (kind == NOSHI_PREVIEW_FILE) {
        [_voiceAction setProgress:1];
        [_voiceAction setIcon:NoshiMediaIconFile animated:YES];
        return;
    }
    if (kind == NOSHI_PREVIEW_VOICE || kind == NOSHI_PREVIEW_AUDIO) {
        [self syncVoiceActionAnimated:YES];
        return;
    }
    [_play setProgress:1];
    if (kind == NOSHI_PREVIEW_GIF && _animating && ![self spoilerHidesItem:_item]) {
        [self startGif];
        return;
    }
    if (_item.kind == NoshiChatItemRound && _playWhenLoaded) {
        _playWhenLoaded = NO;
        [self beginRoundAtPath:_loadedPath];
        return;
    }
    [_play setIcon:NoshiMediaIconPlay animated:YES];
}

- (void)cancelMediaTransfer {
    ++_loadToken;
    [_media cancelPathRequest:_loadRequest];
    _loadRequest = 0;
    _playWhenLoaded = NO;
    _body.fileProgressText = nil;
    [_body setNeedsDisplay];
}

- (void)showFileProgress:(float)fraction {
    NoshiMedia *content = _item.message.media;
    if (content.kind != NOSHI_PREVIEW_FILE || content.size <= 0) return;
    long long loaded = (long long)((double)content.size * MAX(0, MIN(1, fraction)));
    _body.fileProgressText = [NSString stringWithFormat:@"%@ / %@", NoshiFileSizeText(loaded), NoshiFileSizeText(content.size)];
    [_body setNeedsDisplay];
}

/* the cell goes to another row, or ends */
- (void)cancelMediaLoad {
    /* a download the user asked for by a tap goes on in the cache when the row or the chat goes away, its bytes are
       wanted; the token drop below only mutes the callbacks of this cell */
    if (_loadRequest && _loadAsked) {
        ++_loadToken;
        _loadRequest = 0;
        _playWhenLoaded = NO;
        _body.fileProgressText = nil;
    } else {
        [self cancelMediaTransfer];
    }
    _loadAsked = NO;
    [_loadedPath release];
    _loadedPath = nil;
    _loadFailed = NO;
    _loadProgress = 0;
    _photoLoadShown = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showPhotoLoading) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hidePhotoLoading) object:nil];
}

/* a tap on a video that is not here yet brings it, with the ring turning on the button, and a second tap lets it
   go; a video that cannot be brought here (it is past the limit of the cache, or the file did not come) opens at
   once */
- (BOOL)tappedMediaButton {
    noshi_preview_kind kind = _item.message.media.kind;
    if (kind == NOSHI_PREVIEW_PHOTO || _play.hidden || _loadedPath) return NO;
    if (_loadRequest) {
        [self cancelMediaTransfer];
        [_play setIcon:NoshiMediaIconDownload animated:YES];
        return YES;
    }
    [self startMediaLoad:YES];
    return !_loadFailed;
}

/* a tap on a document that is here opens it; on one that is not, it brings it with the ring turning on the button,
   and a second tap lets it go */
- (void)tappedFileButton {
    if ([self uploading]) {
        [self cancelSending];
        return;
    }
    if (_loadedPath) {
        [_delegate messageCell:self didOpenFileAtPath:_loadedPath name:_item.message.media.name];
        return;
    }
    if (_loadRequest) {
        [self cancelMediaTransfer];
        [_voiceAction setIcon:NoshiMediaIconDownload animated:YES];
        return;
    }
    [self startMediaLoad:YES];
}

#pragma mark voice button

- (void)prepareVoiceActionForItem:(NoshiChatItem *)item bubble:(CGRect)bubble {
    noshi_preview_kind kind = item.message.media.kind;
    if (item.call || item.content != NoshiChatItemContentFile || NoshiMessageIsViewOnce(item.message) || (kind != NOSHI_PREVIEW_VOICE && kind != NOSHI_PREVIEW_AUDIO && kind != NOSHI_PREVIEW_FILE)) return;
    CGRect icon = item.fileFrame;
    _voiceAction.frame = CGRectMake(bubble.origin.x + icon.origin.x, bubble.origin.y + icon.origin.y, VOICE_BUTTON, VOICE_BUTTON);
    _voiceAction.discColor = NoshiColorAccent();
    _voiceAction.hidden = NO;
    /* a voice note comes by itself, a song waits to be played, and a document waits to be asked for: the arrow, then the page once it is here */
    [self prepareMediaButtonLoading:kind == NOSHI_PREVIEW_VOICE];
    if (kind == NOSHI_PREVIEW_FILE) [_voiceAction setIcon:_loadRequest || [self uploading] ? NoshiMediaIconCancel : (_loadedPath ? NoshiMediaIconFile : NoshiMediaIconDownload) animated:NO];
    else [self syncVoiceActionAnimated:NO];
}

/* the glyph follows the player when this is its song, and the file when it is not */
- (void)syncVoiceActionAnimated:(BOOL)animated {
    NoshiMedia *media = _item.message.media;
    if (_voiceAction.hidden) return;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    if ([player isCurrentTrack:media] && player.state != NoshiMusicStateFailed) {
        switch (player.state) {
        case NoshiMusicStateLoading:
            [_voiceAction setIcon:NoshiMediaIconCancel animated:animated];
            [_voiceAction setProgress:player.loadProgress];
            break;
        case NoshiMusicStatePlaying: [_voiceAction setIcon:NoshiMediaIconPause animated:animated]; break;
        default: [_voiceAction setIcon:NoshiMediaIconPlay animated:animated]; break;
        }
        return;
    }
    if (_loadRequest) [_voiceAction setIcon:NoshiMediaIconCancel animated:animated];
    else [_voiceAction setIcon:_loadedPath ? NoshiMediaIconPlay : NoshiMediaIconDownload animated:animated];
}

#pragma mark round message

- (NSString *)roundKey {
    return _item.message.media.file.key;
}

/* the cell stops drawing the circle and the playback goes on: the row scrolled away, was taken for another message or its chat was
   left, and the circle floats until the person ends it. the button goes back to the triangle */
- (void)detachRound {
    [_roundTimer invalidate];
    _roundTimer = nil;
    ((AVPlayerLayer *)_roundView.layer).player = nil;
    [_roundView removeFromSuperview];
    [_roundView release];
    _roundView = nil;
    [_roundRing removeFromSuperlayer];
    [_roundRing release];
    _roundRing = nil;
    /* the button went with the circle while it was big, and sits on the picture again */
    _play.transform = CGAffineTransformIdentity;
    [_roundSpeed removeFromSuperview];
    [_roundSpeed release];
    self.layer.zPosition = 0;
    _roundSpeed = nil;
    if (_item.kind == NoshiChatItemRound) {
        _play.hidden = NO;
        [_play setIcon:_loadedPath ? NoshiMediaIconPlay : NoshiMediaIconDownload animated:_play.window != nil];
    }
    [[NoshiRoundPlayback sharedPlayback] releaseHost:self];
}

- (void)startRound {
    if ([[NoshiRoundPlayback sharedPlayback] isActiveKey:[self roundKey]]) return;
    [self toggleRound];
}

/* the speed chip on a playing circle follows the speed the player keeps; the rate of the video is the playback's */
- (void)applyRoundSpeed {
    [_roundSpeed setTitle:NoshiSpeedText([NoshiMusicPlayer sharedPlayer].speed) forState:UIControlStateNormal];
}

- (void)cycleRoundSpeed {
    [[NoshiMusicPlayer sharedPlayer] cycleSpeed];
}

/* a row that comes back on screen while its video message plays takes the circle from the one that floats */
- (void)adoptRound {
    if (_roundView || _item.kind != NoshiChatItemRound || !self.window || _picture.hidden) return;
    if (![[NoshiRoundPlayback sharedPlayback] isActiveKey:[self roundKey]]) return;
    [self showRound];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self adoptRound];
    else if (_roundView) [self detachRound];
}

- (void)roundPlaybackChanged:(NSNotification *)note {
    (void)note;
    if (!_roundView) return;
    NoshiRoundPlayback *playback = [NoshiRoundPlayback sharedPlayback];
    if (![playback isActiveKey:[self roundKey]]) {
        [self settleRoundThenDetach];
        return;
    }
    [_play setIcon:playback.playing ? NoshiMediaIconNone : NoshiMediaIconPlay animated:YES];
}

/* a tap on the circle starts the video, pauses it and resumes it; one that was let go or never arrived is asked
   for again by a tap */
- (void)toggleRound {
    if ([[NoshiRoundPlayback sharedPlayback] isActiveKey:[self roundKey]]) {
        [[NoshiRoundPlayback sharedPlayback] togglePause];
        return;
    }
    if (!_item.message.media.file) return;
    if (_loadedPath) {
        [self beginRoundAtPath:_loadedPath];
        return;
    }
    if (_loadRequest) {
        if (_playWhenLoaded) {
            [self cancelMediaTransfer];
            [_play setIcon:NoshiMediaIconDownload animated:YES];
        } else {
            _loadAsked = YES;
            _playWhenLoaded = YES;
        }
        return;
    }
    _playWhenLoaded = YES;
    [self startMediaLoad:YES];
}

- (void)beginRoundAtPath:(NSString *)path {
    NSURL *url = NoshiPlayableLink(path, @"mp4", @"round");
    id<NoshiRoundChain> chain = [_delegate conformsToProtocol:@protocol(NoshiRoundChain)] ? (id<NoshiRoundChain>)_delegate : nil;
    if (!url || ![[NoshiRoundPlayback sharedPlayback] beginWithURL:url key:[self roundKey] chain:chain]) {
        [self detachRound];
        return;
    }
    [self showRound];
}

/* the circle of the video over the picture, with the ring of the progress and the speed chip. the playback is already going */
- (void)showRound {
    NoshiRoundPlayback *playback = [NoshiRoundPlayback sharedPlayback];
    [self detachRound];
    if (!self.window) return;
    [playback setHost:self];
    [_play setIcon:playback.playing ? NoshiMediaIconNone : NoshiMediaIconPlay animated:NO];
    _roundView = [[NoshiRoundVideoView alloc] initWithFrame:_picture.frame];
    _roundView.userInteractionEnabled = NO;
    _roundView.layer.cornerRadius = _picture.frame.size.width / 2;
    _roundView.layer.masksToBounds = YES;
    ((AVPlayerLayer *)_roundView.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
    ((AVPlayerLayer *)_roundView.layer).player = playback.player;
    [self.contentView insertSubview:_roundView aboveSubview:_picture];
    _roundRing = [[CAShapeLayer layer] retain];
    /* the layer is the size of the picture and stands on it, so the turn that starts the stroke at the top is
       about the middle of the picture */
    _roundRing.frame = _picture.frame;
    CGRect ring = CGRectInset(_roundRing.bounds, 1.5, 1.5);
    _roundRing.path = [UIBezierPath bezierPathWithOvalInRect:ring].CGPath;
    _roundRing.fillColor = NULL;
    _roundRing.strokeColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    _roundRing.lineWidth = 3;
    _roundRing.lineCap = kCALineCapRound;
    _roundRing.strokeEnd = [playback progress];
    /* the stroke starts at the top and runs clockwise, which a path from three o'clock does not */
    _roundRing.transform = CATransform3DMakeRotation((CGFloat)(-M_PI / 2), 0, 0, 1);
    [self.contentView.layer addSublayer:_roundRing];
    _roundSpeed = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _roundSpeed.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _roundSpeed.layer.cornerRadius = 11;
    _roundSpeed.titleLabel.font = NoshiFontSemibold(12);
    _roundSpeed.frame = CGRectMake(CGRectGetMidX(_picture.frame) - 20, CGRectGetMaxY(_picture.frame) - 34, 40, 22);
    [_roundSpeed addTarget:self action:@selector(cycleRoundSpeed) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_roundSpeed];
    [self applyRoundSpeed];
    [self growRoundAnimated:YES];
    _roundTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(roundTick:) userInfo:nil repeats:YES];
}

/* a video message that plays swells, and settles back when it stops. the row keeps its height, so the circle may grow only into
   the room its own row has above (the gap to the row before) and below (the line of the time): that keeps it off the neighbours,
   and it moves down or up by the difference so it fills that room evenly. the pause button and the speed chip follow the
   circle, since they are laid out for the picture, not for where the circle ends up */
- (void)growRoundAnimated:(BOOL)animated {
    CGFloat side = _picture.frame.size.width, width = self.contentView.bounds.size.width, margin = 6;
    CGFloat above = CGRectGetMinY(_picture.frame), below = _item.height - CGRectGetMaxY(_picture.frame);
    if (!CGRectIsEmpty(_item.reactionFrame))
        below = MIN(below, CGRectGetMinY(_item.reactionFrame) - CGRectGetMaxY(_picture.frame) - 4);
    CGFloat grow = 1, shift = 0, dy = 0;
    if (side >= 1 && width >= side && above >= 0 && below >= 0 && !NoshiReduceMotionEnabled()) {
        grow = MAX(1, MIN(1.5, MIN((width - 2 * margin) / side, 1 + (above + below) / side)));
        /* the rows on a tablet are airy but the circle is big, so the room of its own row gave a swell too small to notice. the circle is drawn over its neighbours while it
           plays, so a tablet lets it swell a fifth past that room */
        if (NoshiIsPad()) grow = MAX(grow, MIN(1.2, (width - 2 * margin) / side));
    }
    /* the swell reaches up and down in the proportion of the room on each side, so the center moves by half of the difference */
    if (grow >= 1.05) {
        CGFloat extra = side * (grow - 1), up = above + below > 0 ? extra * above / (above + below) : extra / 2;
        dy = extra / 2 - up;
        CGFloat half = side * grow / 2, middle = CGRectGetMidX(_picture.frame);
        if (middle - half < margin) shift = margin - (middle - half);
        else if (middle + half > width - margin) shift = (width - margin) - (middle + half);
    } else grow = 1;
    self.clipsToBounds = NO;
    self.contentView.clipsToBounds = NO;
    self.layer.zPosition = grow > 1 ? 10 : 0;
    CGRect bounds = CGRectMake(0, 0, _picture.frame.size.width, _picture.frame.size.height);
    CGPoint center = CGPointMake(CGRectGetMidX(_picture.frame), CGRectGetMidY(_picture.frame));
    _roundView.bounds = bounds;
    _roundView.center = center;
    _roundView.layer.cornerRadius = side / 2;
    _roundSpeed.transform = CGAffineTransformIdentity;
    _roundSpeed.frame = CGRectMake(center.x - 20, CGRectGetMaxY(_picture.frame) - 34, 40, 22);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _roundRing.bounds = bounds;
    _roundRing.position = center;
    _roundRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 1.5, 1.5)].CGPath;
    [CATransaction commit];
    CATransform3D ring = CATransform3DMakeTranslation(shift, dy, 0);
    ring = CATransform3DScale(ring, grow, grow, 1);
    ring = CATransform3DRotate(ring, (CGFloat)(-M_PI / 2), 0, 0, 1);
    /* the ring is a layer of its own, so it takes the same time and curve as the circle it rims, and not the jump that left the video swelling inside a ring already grown */
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:ROUND_SWELL_SECONDS];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    _roundRing.transform = ring;
    [CATransaction commit];
    CGAffineTransform view = CGAffineTransformScale(CGAffineTransformMakeTranslation(shift, dy), grow, grow);
    CGAffineTransform speed = CGAffineTransformMakeTranslation(shift, dy + side * (grow - 1) / 2);
    CGAffineTransform button = CGAffineTransformMakeTranslation(shift, dy);
    void (^change)(void) = ^{
        _roundView.transform = view;
        _roundSpeed.transform = speed;
        _play.transform = button;
    };
    if (animated) [UIView animateWithDuration:ROUND_SWELL_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:change completion:nil];
    else change();
}

/* a circle that stops settles back to its size before it goes, as it swelled; a row that is reused or leaves the screen drops it at once */
- (void)settleRoundThenDetach {
    NoshiRoundVideoView *view = _roundView;
    if (!view || !self.window || NoshiReduceMotionEnabled()) {
        [self detachRound];
        return;
    }
    [_roundTimer invalidate];
    _roundTimer = nil;
    [CATransaction begin];
    [CATransaction setAnimationDuration:ROUND_SWELL_SECONDS];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    _roundRing.transform = CATransform3DMakeRotation((CGFloat)(-M_PI / 2), 0, 0, 1);
    [CATransaction commit];
    [UIView animateWithDuration:ROUND_SWELL_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        view.transform = CGAffineTransformIdentity;
        _roundSpeed.transform = CGAffineTransformIdentity;
        _play.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        (void)finished;
        if (_roundView == view) [self detachRound];
    }];
}

- (void)roundTick:(NSTimer *)timer {
    (void)timer;
    _roundRing.strokeEnd = [[NoshiRoundPlayback sharedPlayback] progress];
}

/* a tap on an animation starts it from the beginning: a sticker that plays on its own goes on looping as it did, anything else (an emoji, or a sticker that stands still under the
   power saving settings) plays once */
- (void)replayAnimation {
    if (_slots) {
        [_slots playThrow];
    } else if (_item.kind == NoshiChatItemSticker && [self playsOnItsOwn]) {
        [_lottie setPlaying:NO];
        [_lottie setPlaying:YES];
    } else {
        [_lottie playOnce];
    }
}

- (void)setAnimating:(BOOL)animating {
    if (_item.giftCard) {
        _animating = animating;
        [_giftCardView setActive:animating];
        return;
    }
    if (_item.message.media.kind == NOSHI_PREVIEW_GIF) {
        _animating = animating && (_gifPlayRequested || [self playsOnItsOwn]) && ![self spoilerHidesItem:_item];
        if (_animating) [self startGif];
        else [self stopGif];
        return;
    }
    if (animating && (_item.kind == NoshiChatItemEmoji || _item.kind == NoshiChatItemSticker) && ![self playsOnItsOwn]) animating = NO;
    _animating = animating;
    if (animating && !_activationDeferred && _pendingLottie) [self setActivationDeferred:NO];
    if (_item.kind == NoshiChatItemSticker && _item.message.media.stickerFormat == NOSHI_STICKER_VIDEO) {
        if (!animating && _lottie) { [self discardLottie]; _picture.hidden = NO; }
        else if (animating && !_lottie && !_pendingLottie) [self loadLottieFile:_item.message.media.file];
    }
    if (_slots) {
        /* the machine throws once when it comes into view and rests on the result; one that waits for its result spins */
        if (animating && _item.message.media.diceValue > 0 && !_emojiPlayed) {
            _emojiPlayed = YES;
            [_slots playThrow];
        } else if (animating && _item.message.media.diceValue == 0) {
            [_slots setActive:YES];
        } else {
            [_slots setActive:NO];
            if (animating) [_slots showRest];
        }
    } else if (_item.kind == NoshiChatItemEmoji) {
        /* an emoji plays once when it comes into view, a tap plays it again */
        BOOL waitingDice = _item.message.media.kind == NOSHI_PREVIEW_DICE && _item.message.media.diceValue == 0;
        if (waitingDice) {
            /* a game emoji whose result has not come back loops until it does */
            [_lottie setPlaying:animating];
        } else if (animating && _lottie && !_emojiPlayed) {
            _emojiPlayed = YES;
            [_lottie playOnce];
        } else if (!animating) [_lottie setPlaying:NO];
    } else [_lottie setPlaying:animating];
}

- (void)tappedGif {
    if (_gifPlayer) return;
    if (_loadRequest) {
        if (!_loadAsked) {
            _loadAsked = YES;
            _gifPlayRequested = YES;
            [self setAnimating:YES];
            return;
        }
        _gifPlayRequested = NO;
        [self cancelMediaTransfer];
        [_play setIcon:NoshiMediaIconDownload animated:YES];
        return;
    }
    if (!_item.message.media.file) return;
    _gifFailed = NO;
    _gifPlayRequested = YES;
    [self setAnimating:YES];
    if (!_loadedPath) [self startMediaLoad:YES];
}

/* telegram animations are silent mp4 documents; AVFoundation on ios 5-10 needs an extension on their cache files */
- (void)startGif {
    if (_gifPlayer || _gifFailed || !_animating || _activationDeferred || !_loadedPath || [self spoilerHidesItem:_item]) return;
    NSString *slot = [NSString stringWithFormat:@"gif-%p", self];
    _gifURL = [NoshiPlayableLink(_loadedPath, @"mp4", slot) retain];
    if (!_gifURL) { _gifFailed = YES; return; }
    /* an item with an audio track takes the audio session when it plays, even with its volume at zero, and that stops the music of other apps; the item gets the picture alone */
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:_gifURL options:nil];
    NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *video = videoTracks.count ? [videoTracks objectAtIndex:0] : nil;
    AVMutableComposition *silent = [AVMutableComposition composition];
    AVMutableCompositionTrack *picture = video ? [silent addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid] : nil;
    NSError *composeError = nil;
    if (!picture || ![picture insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration) ofTrack:video atTime:kCMTimeZero error:&composeError]) {
        NSLog(@"noshigram: inline animation has no picture to play: %@", composeError);
        _gifFailed = YES;
        [[NSFileManager defaultManager] removeItemAtPath:_gifURL.path.stringByDeletingLastPathComponent error:NULL];
        [_gifURL release]; _gifURL = nil;
        return;
    }
    picture.preferredTransform = video.preferredTransform;
    /* an AVPlayer takes the audio session the first time it plays, even a player with no sound track, and the default session of the application does not mix, so the music that
       played (of another application, or ours left on the session of its own) stopped as the first animation of the chat began. a session that mixes is taken first; a call, a recording
       and a song of ours are on sessions of their own and are left as they are */
    NSString *category = NoshiAudioSessionCategory();
    if (![category isEqualToString:NoshiAudioCategoryPlayAndRecord()] && ![category isEqualToString:NoshiAudioCategoryPlayback()]) NoshiAudioSessionBeginMixedPlayback();
    _gifItem = [[AVPlayerItem playerItemWithAsset:silent] retain];
    _gifPlayer = [[AVPlayer playerWithPlayerItem:_gifItem] retain];
    _gifPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    _gifView = [[NoshiRoundVideoView alloc] initWithFrame:_picture.frame];
    _gifView.userInteractionEnabled = NO;
    NoshiMirrorCorners(_gifView, _picture);
    _gifView.clipsToBounds = YES;
    ((AVPlayerLayer *)_gifView.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
    ((AVPlayerLayer *)_gifView.layer).player = _gifPlayer;
    [self.contentView insertSubview:_gifView aboveSubview:_picture];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gifEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_gifItem];
    [_gifItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:&NoshiGifStatusContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &NoshiGifStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    NoshiWeakReference *weak = _weak;
    dispatch_async(dispatch_get_main_queue(), ^{
        NoshiMessageCell *cell = weak.target;
        if (!cell || object != cell->_gifItem) return;
        if (cell->_gifItem.status == AVPlayerItemStatusReadyToPlay) {
            cell->_play.hidden = YES;
            if (cell->_animating) [cell->_gifPlayer play];
        } else if (cell->_gifItem.status == AVPlayerItemStatusFailed) {
            NSLog(@"noshigram: inline animation failed: %@", cell->_gifItem.error);
            cell->_gifFailed = YES;
            [cell stopGif];
        }
    });
}

- (void)gifEnded:(NSNotification *)note {
    if (note.object != _gifItem || !_animating) return;
    [_gifPlayer seekToTime:kCMTimeZero];
    [_gifPlayer play];
}

- (void)stopGif {
    if (_gifItem) {
        [_gifItem removeObserver:self forKeyPath:@"status" context:&NoshiGifStatusContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_gifItem];
    }
    [_gifPlayer pause];
    ((AVPlayerLayer *)_gifView.layer).player = nil;
    [_gifView removeFromSuperview];
    [_gifView release]; _gifView = nil;
    [_gifPlayer release]; _gifPlayer = nil;
    [_gifItem release]; _gifItem = nil;
    if (_gifURL) [[NSFileManager defaultManager] removeItemAtPath:_gifURL.path.stringByDeletingLastPathComponent error:NULL];
    [_gifURL release]; _gifURL = nil;
    if (_item.message.media.kind == NOSHI_PREVIEW_GIF) {
        _play.hidden = NO;
        [_play setIcon:_loadRequest ? NoshiMediaIconCancel : (_loadedPath ? NoshiMediaIconPlay : NoshiMediaIconDownload) animated:NO];
    }
}

#pragma mark swipe to reply

- (BOOL)replySwipeActive {
    return _swipe.state == UIGestureRecognizerStateBegan || _swipe.state == UIGestureRecognizerStateChanged;
}

- (UITableView *)replyTable {
    for (UIView *view = self.superview; view; view = view.superview)
        if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    return nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    UITableView *table = [self replyTable];
    return table && ((gesture == _swipe && other == table.panGestureRecognizer) || (other == _swipe && gesture == table.panGestureRecognizer));
}

- (void)resumeReplyTable {
    if (!_pausedTablePan) return;
    _pausedTablePan.enabled = YES;
    [_pausedTablePan release];
    _pausedTablePan = nil;
}

/* every message is answered by a leftward swipe; vertical movement stays with the table */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer == _seekPan) {
        if (_selecting || !_item.message) return NO;
        CGPoint point = [recognizer locationInView:self.contentView];
        if (_item.kind == NoshiChatItemRound && _roundView) {
            CGFloat x = point.x - CGRectGetMidX(_picture.frame), y = point.y - CGRectGetMidY(_picture.frame);
            CGFloat radius = _picture.frame.size.width / 2;
            CGFloat distance = hypot(x, y);
            return distance >= MAX(0, radius - 32) && distance <= radius + 12;
        }
        if (_item.content == NoshiChatItemContentFile && _item.message.media.kind == NOSHI_PREVIEW_VOICE) {
            NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
            CGPoint body = [recognizer locationInView:_body];
            if (!_item.message.outgoing) body.x -= _body.tailWidth;
            return [player isCurrentTrack:_item.message.media] &&
                (player.state == NoshiMusicStatePlaying || player.state == NoshiMusicStatePaused) &&
                CGRectContainsPoint(CGRectInset([_body waveRect], 0, -8), body);
        }
        return NO;
    }
    if (recognizer == _handlePan) return [self handleNear:[recognizer locationInView:_body]] != 0;
    if (recognizer != _swipe) return YES;
    if (_selecting || _pick.length || !_item.message || _item.kind == NoshiChatItemPill || ![_delegate messageCellCanSwipeReply:self]) return NO;
    UITableView *table = [self replyTable];
    CGPoint velocity = [_swipe velocityInView:self];
    if (table.decelerating || (table.dragging && fabs(velocity.y) * 3 >= fabs(velocity.x))) return NO;
    return noshi_motion_reply_swipe_begins(velocity.x, velocity.y);
}

- (void)seekDragged:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateBegan && pan.state != UIGestureRecognizerStateChanged && pan.state != UIGestureRecognizerStateEnded) return;
    if (_item.kind == NoshiChatItemRound && _roundView) {
        CGPoint point = [pan locationInView:self.contentView];
        CGFloat angle = atan2(point.y - CGRectGetMidY(_picture.frame), point.x - CGRectGetMidX(_picture.frame)) + (CGFloat)M_PI / 2;
        if (angle < 0) angle += (CGFloat)(2 * M_PI);
        CGFloat fraction = angle / (CGFloat)(2 * M_PI);
        _roundRing.strokeEnd = fraction;
        [[NoshiRoundPlayback sharedPlayback] seekToFraction:fraction];
    } else if (_item.message.media.kind == NOSHI_PREVIEW_VOICE) {
        CGPoint point = [pan locationInView:_body];
        if (!_item.message.outgoing) point.x -= _body.tailWidth;
        CGRect wave = [_body waveRect];
        if (wave.size.width > 0) [[NoshiMusicPlayer sharedPlayer] seekToFraction:(float)((point.x - wave.origin.x) / wave.size.width)];
    }
}

/* the row of somebody else sits right of the selection circle while messages are picked. it is a transform of the sublayers, as the swipe to reply is: the cell
   of older systems sets the frame of its content view on every layout, which takes a transform of the view itself back out again, and the rows then stood under the circles */
- (CATransform3D)restingTransform {
    return _selecting && !_item.message.outgoing && [self selectable] ? CATransform3DMakeTranslation(SELECT_SHIFT, 0, 0) : CATransform3DIdentity;
}

- (void)resetSwipe {
    ++_swipeGeneration;
    [self resumeReplyTable];
    [self.contentView.layer removeAllAnimations];
    [_swipeDisc.layer removeAllAnimations];
    [_swipeFill removeAllAnimations];
    [self clearSwipeState];
    self.contentView.transform = CGAffineTransformIdentity;
    self.contentView.layer.sublayerTransform = [self restingTransform];
    _swipeDisc.alpha = 0;
}

- (void)clearSwipeState {
    _swipeShown = NO;
    _swipeArmed = NO;
    _swipePull = 0;
    [self clearSwipeVisuals];
}

/* the ring and the fill go back to empty without animating, for the next pull */
- (void)clearSwipeVisuals {
    [_swipeFill removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _swipeRing.strokeEnd = 0;
    _swipeFill.opacity = 0;
    [CATransaction commit];
}

/* the tick the answer gives when it becomes armed; the generator is found at run time, since it came with ios 10 */
static void NoshiSwipeTick(void) {
    Class generator = NSClassFromString(@"UIImpactFeedbackGenerator");
    if (!generator) return;
    id feedback = [[[generator alloc] init] autorelease];
    if ([feedback respondsToSelector:@selector(impactOccurred)]) [feedback performSelector:@selector(impactOccurred)];
}

/* a message that has a number on the server can be picked; a date, a service line and a message still on its way cannot */
- (BOOL)selectable {
    return _item.message && _item.kind != NoshiChatItemPill && _item.message.messageId > 0;
}

- (void)selectTapped {
    if ([_delegate respondsToSelector:@selector(messageCellDidToggleSelection:)]) [_delegate messageCellDidToggleSelection:self];
}

- (UIImage *)contentSnapshot {
    CGSize size = self.contentView.bounds.size;
    if (size.width <= 0 || size.height <= 0) return nil;
    CGAffineTransform pictureTransform = _picture.transform;
    /* AVPlayerLayer does not render into the menu snapshot, so its cover must follow the enlarged video */
    if (_roundView) _picture.transform = _roundView.transform;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [self.contentView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (_roundView) _picture.transform = pictureTransform;
    return image;
}

/* setSelecting runs while the table configures the cell, before it gives the cell its row height, so the cover took the height of the row the cell showed last and its bottom
   part answered no touch; it follows the bounds of the cell from here on */
- (void)layoutSubviews {
    [super layoutSubviews];
    _selectCover.frame = self.bounds;
}

- (void)setSelecting:(BOOL)selecting selected:(BOOL)selected animated:(BOOL)animated {
    _selecting = selecting;
    _selected = selected;
    BOOL show = selecting && [self selectable];
    _selectCover.hidden = !show;
    _selectCover.frame = self.bounds;
    _selectMark.hidden = !show;
    CGRect bubble = _item.bubbleFrame;
    _selectMark.center = CGPointMake(8 + SELECT_MARK / 2, CGRectGetMidY(bubble));
    CALayer *layer = self.contentView.layer;
    CATransform3D from = [layer animationForKey:@"noshigram.select"] ? [layer.presentationLayer sublayerTransform] : layer.sublayerTransform;
    CATransform3D to = [self restingTransform];
    [layer removeAnimationForKey:@"noshigram.select"];
    layer.sublayerTransform = to;
    if (animated && !CATransform3DEqualToTransform(from, to)) {
        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
        slide.fromValue = [NSValue valueWithCATransform3D:from];
        slide.toValue = [NSValue valueWithCATransform3D:to];
        slide.duration = 0.18;
        [layer addAnimation:slide forKey:@"noshigram.select"];
    }
    void (^apply)(void) = ^{
        _selectMark.backgroundColor = selected ? NoshiColorAccent() : [UIColor colorWithWhite:0 alpha:0.32];
        _selectMark.layer.borderColor = (selected ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.95]).CGColor;
        _selectCheck.alpha = selected ? 1 : 0;
    };
    if (animated) [UIView animateWithDuration:0.18 animations:apply];
    else apply();
}

- (CGPoint)swipeDiscCenterForPull:(CGFloat)pull {
    (void)pull;
    CGFloat right = CGRectGetMaxX(_item.bubbleFrame);
    return CGPointMake(MIN(self.bounds.size.width - SWIPE_DISC / 2, right + SWIPE_DISC / 2 + 6), CGRectGetMidY(_item.bubbleFrame));
}

/* the ring grows over the 30 points after the disc shows, and the fill swells in when the answer is armed or leaves when the finger comes back under the line */
- (void)updateSwipeForPull:(CGFloat)pull {
    BOOL shown = pull >= SWIPE_SHOW;
    if (shown != _swipeShown) {
        _swipeShown = shown;
        if (shown) {
            _swipeDisc.transform = CGAffineTransformMakeScale(0.3f, 0.3f);
            NoshiAnimateView(_swipeDisc, CGAffineTransformIdentity, 1, NOSHI_MOTION_SPRING, nil);
        } else {
            NoshiAnimateView(_swipeDisc, CGAffineTransformMakeScale(0.3f, 0.3f), 0, NOSHI_MOTION_EXIT, nil);
        }
    }
    BOOL armed = pull >= SWIPE_TRIGGER;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _swipeRing.strokeEnd = armed ? 1 : MAX(0, MIN(1, (pull - SWIPE_SHOW) / (SWIPE_TRIGGER - SWIPE_SHOW)));
    [CATransaction commit];
    if (armed == _swipeArmed) return;
    _swipeArmed = armed;
    if (armed) NoshiSwipeTick();
    CFTimeInterval duration = NoshiReduceMotionEnabled() ? 0 : 0.28;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _swipeFill.opacity = armed ? 1 : 0;
    [CATransaction commit];
    CAKeyframeAnimation *swell = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    swell.values = armed ? [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.3f], [NSNumber numberWithFloat:1.12f], [NSNumber numberWithFloat:1], nil]
                         : [NSArray arrayWithObjects:[NSNumber numberWithFloat:1], [NSNumber numberWithFloat:0.3f], nil];
    swell.keyTimes = armed ? [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.6f], [NSNumber numberWithFloat:1], nil]
                           : [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:1], nil];
    swell.duration = duration;
    swell.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    if (duration > 0) [_swipeFill addAnimation:swell forKey:@"noshigram.swipe.fill"];
}

- (void)swiped:(UIPanGestureRecognizer *)pan {
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
    case UIGestureRecognizerStateChanged: {
        if (pan.state == UIGestureRecognizerStateBegan) {
            ++_swipeGeneration;
            [self.contentView.layer removeAnimationForKey:@"noshigram.swipe.return"];
            UIPanGestureRecognizer *tablePan = [self replyTable].panGestureRecognizer;
            if (tablePan.enabled) {
                _pausedTablePan = [tablePan retain];
                tablePan.enabled = NO;
            }
        }
        /* the row follows the finger in both directions: the way back gives the pull back, and the disc leaves with it */
        CGFloat pull = (CGFloat)noshi_motion_reply_swipe_pull([pan translationInView:self].x);
        _swipePull = pull;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.contentView.layer.sublayerTransform = CATransform3DMakeTranslation(-pull, 0, 0);
        [CATransaction commit];
        _swipeDisc.center = [self swipeDiscCenterForPull:pull];
        [self updateSwipeForPull:pull];
        break;
    }
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed: {
        [self resumeReplyTable];
        BOOL answer = pan.state == UIGestureRecognizerStateEnded && _swipePull >= SWIPE_TRIGGER;
        CGFloat duration = NoshiReduceMotionEnabled() ? 0 : MIN(0.32, MAX(SWIPE_BACK_SECONDS, _swipePull / 500.0));
        _swipeShown = NO;
        _swipeArmed = NO;
        _swipePull = 0;
        /* the row and the disc go back together, slowing down toward the end, as the 180 ms return of exteraless; the ring and the fill empty once it is gone, unless
           a new pull has begun by then */
        CGPoint home = [self swipeDiscCenterForPull:0];
        NSUInteger generation = _swipeGeneration;
        CABasicAnimation *returnMessage = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
        returnMessage.fromValue = [NSValue valueWithCATransform3D:self.contentView.layer.sublayerTransform];
        returnMessage.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        returnMessage.duration = duration;
        returnMessage.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.contentView.layer.sublayerTransform = CATransform3DIdentity;
        [CATransaction commit];
        if (returnMessage.duration > 0) [self.contentView.layer addAnimation:returnMessage forKey:@"noshigram.swipe.return"];
        CALayer *visibleDisc = [_swipeDisc.layer presentationLayer];
        CGFloat visibleAlpha = visibleDisc ? visibleDisc.opacity : _swipeDisc.alpha;
        CATransform3D visibleTransform = visibleDisc ? visibleDisc.transform : _swipeDisc.layer.transform;
        [_swipeDisc.layer removeAnimationForKey:@"noshigram.motion"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _swipeDisc.layer.transform = visibleTransform;
        _swipeDisc.alpha = visibleAlpha;
        [CATransaction commit];
        [UIView animateWithDuration:duration delay:0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            _swipeDisc.center = home;
            _swipeDisc.alpha = 0;
        } completion:^(BOOL finished) {
            if (generation == _swipeGeneration && !_swipeShown) {
                [self clearSwipeVisuals];
                if (finished && answer) [_delegate messageCellDidSwipeReply:self];
            }
        }];
        break;
    }
    default:
        break;
    }
}

- (CGRect)chipFrameOfReaction:(NoshiReaction *)reaction inView:(UIView *)view {
    return [_reactions frameOfReaction:reaction inView:view];
}

/* whether the chat shows the time of a reaction on a hold of its chip, and then the hold is the chip's and not the bubble's */
- (BOOL)reactionTimeShown {
    return [_delegate respondsToSelector:@selector(messageCellShowsReactionTime:)] && [_delegate messageCellShowsReactionTime:self] &&
           [_delegate respondsToSelector:@selector(messageCell:didHoldReaction:)];
}

- (void)longPressed:(UIGestureRecognizer *)press {
    /* the controller knows what can be done to the message, so a message that offers nothing just shows no menu */
    if (press.state != UIGestureRecognizerStateBegan || !_item.message || _item.kind == NoshiChatItemPill) return;
    /* the press that came second in the same touch finds the menu already open */
    UIGestureRecognizer *other = press == _forcePress ? _longPress : _forcePress;
    if (other.state == UIGestureRecognizerStateBegan || other.state == UIGestureRecognizerStateChanged) return;
    CGPoint point = [press locationInView:self.contentView];
    if (!_reactions.hidden && [self reactionTimeShown] && [_reactions chipContainsPoint:[self.contentView convertPoint:point toView:_reactions]]) return;
    _pressPoint = [press locationInView:_body];
    if (CGRectContainsPoint(_item.bubbleFrame, point)) [_delegate messageCellDidLongPress:self];
}

- (void)doubleTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded || _selecting || !_item.message) return;
    if ([_delegate respondsToSelector:@selector(messageCellDidDoubleTap:)]) [_delegate messageCellDidDoubleTap:self];
}

- (void)shareTapped {
    [_delegate messageCellDidTapShare:self];
}

- (void)acceptSharing {
    if ([_delegate respondsToSelector:@selector(messageCell:answerSharingRequest:)]) [_delegate messageCell:self answerSharingRequest:YES];
}

- (void)declineSharing {
    if ([_delegate respondsToSelector:@selector(messageCell:answerSharingRequest:)]) [_delegate messageCell:self answerSharingRequest:NO];
}

#pragma mark text selection

/* the point of the bubble, in the coordinates of the text box */
- (CGPoint)layoutPointOfBodyPoint:(CGPoint)point {
    if (!_item.message.outgoing) point.x -= _body.tailWidth;
    return CGPointMake(point.x - _item.textOrigin.x, point.y - _item.textOrigin.y);
}

- (CGPoint)bodyPointOfLayoutPoint:(CGPoint)point {
    point.x += _item.textOrigin.x; point.y += _item.textOrigin.y;
    if (!_item.message.outgoing) point.x += _body.tailWidth;
    return point;
}

- (BOOL)canPickText { return _item.textLayout && _item.textLayout.length > 0 && _item.message && _item.kind != NoshiChatItemPill; }

/* 1 for the handle at the start of the selection, 2 for the one at its end, 0 for neither */
- (NSInteger)handleNear:(CGPoint)bodyPoint {
    if (!_pick.length) return 0;
    NSArray *boxes = [_item.textLayout rectsForRange:_pick];
    if (!boxes.count) return 0;
    CGRect first = [[boxes objectAtIndex:0] CGRectValue], last = [[boxes lastObject] CGRectValue];
    CGPoint start = [self bodyPointOfLayoutPoint:CGPointMake(first.origin.x, first.origin.y - 4)];
    CGPoint end = [self bodyPointOfLayoutPoint:CGPointMake(CGRectGetMaxX(last), CGRectGetMaxY(last) + 4)];
    CGFloat toStart = hypot(bodyPoint.x - start.x, bodyPoint.y - start.y), toEnd = hypot(bodyPoint.x - end.x, bodyPoint.y - end.y);
    if (MIN(toStart, toEnd) > 26) return 0;
    return toStart <= toEnd ? 1 : 2;
}

/* starts a selection on the word under the finger of the long press that opened the menu, or on the first word */
- (void)beginTextSelection {
    if (![self canPickText]) return;
    NoshiTextLayout *layout = _item.textLayout;
    NSUInteger index = [layout characterIndexAtPoint:[self layoutPointOfBodyPoint:_pressPoint]];
    NSRange word = [layout wordRangeAtIndex:index > 0 && index >= layout.length ? layout.length - 1 : index];
    if (!word.length) word = NSMakeRange(0, MIN((NSUInteger)1, layout.length));
    _pick = word;
    _body.pickRange = _pick;
    [_body setNeedsDisplay];
    if (!_handlePan) {
        _handlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDragged:)];
        _handlePan.delegate = self;
        _handlePan.maximumNumberOfTouches = 1;
        [_body addGestureRecognizer:_handlePan];
    }
    _handlePan.enabled = YES;
    UITableView *table = [self replyTable];
    if (table) [table.panGestureRecognizer requireGestureRecognizerToFail:_handlePan];
    [self performSelector:@selector(showPickMenu) withObject:nil afterDelay:0.3];
}

- (void)clearTextSelection {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showPickMenu) object:nil];
    if (!_pick.length) return;
    _pick = NSMakeRange(0, 0);
    _body.pickRange = _pick;
    _handlePan.enabled = NO;
    [_body setNeedsDisplay];
    if ([self isFirstResponder]) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
        [self resignFirstResponder];
    }
}

- (BOOL)hasTextSelection { return _pick.length > 0; }

- (BOOL)canBecomeFirstResponder { return YES; }

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return action == @selector(noshiCopyPick) || action == @selector(noshiQuotePick) || action == @selector(noshiPickAll);
}

- (void)showPickMenu {
    if (!_pick.length || ![self canPickText]) return;
    [self becomeFirstResponder];
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"chat.sel.copy", nil) action:@selector(noshiCopyPick)] autorelease]];
    /* a quote has to be words the message really has, and the chat has to allow an answer */
    if ([_delegate respondsToSelector:@selector(messageCell:didQuoteText:offset:)] && [_delegate messageCellCanSwipeReply:self] && _item.message.messageId > 0) {
        [items addObject:[[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"chat.sel.quote", nil) action:@selector(noshiQuotePick)] autorelease]];
    }
    if (_pick.length < _item.textLayout.length) {
        [items addObject:[[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"chat.sel.all", nil) action:@selector(noshiPickAll)] autorelease]];
    }
    NSArray *boxes = [_item.textLayout rectsForRange:_pick];
    CGRect area = CGRectNull;
    for (NSValue *box in boxes) area = CGRectUnion(area, box.CGRectValue);
    if (CGRectIsNull(area)) return;
    CGPoint corner = [self bodyPointOfLayoutPoint:area.origin];
    CGRect target = [self convertRect:CGRectMake(corner.x, corner.y, area.size.width, area.size.height) fromView:_body];
    UIMenuController *menu = [UIMenuController sharedMenuController];
    menu.menuItems = items;
    [menu setTargetRect:target inView:self];
    [menu setMenuVisible:YES animated:YES];
}

- (NSString *)pickedWords {
    NSRange range = [_item.textLayout textRangeForRange:_pick];
    NSString *text = [_item.textLayout text];
    if (!range.length || NSMaxRange(range) > text.length) return nil;
    return [text substringWithRange:range];
}

- (void)noshiCopyPick {
    NSString *words = [self pickedWords];
    if (words.length) [UIPasteboard generalPasteboard].string = words;
    [self clearTextSelection];
}

- (void)noshiQuotePick {
    NSString *words = [self pickedWords];
    NSRange range = [_item.textLayout textRangeForRange:_pick];
    [self clearTextSelection];
    if (words.length) [_delegate messageCell:self didQuoteText:words offset:(int32_t)range.location];
}

- (void)noshiPickAll {
    _pick = NSMakeRange(0, _item.textLayout.length);
    _body.pickRange = _pick;
    [_body setNeedsDisplay];
    [self performSelector:@selector(showPickMenu) withObject:nil afterDelay:0.05];
}

- (void)handleDragged:(UIPanGestureRecognizer *)pan {
    if (!_pick.length) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        _dragHandle = [self handleNear:[pan locationInView:_body]];
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
        return;
    }
    if (pan.state == UIGestureRecognizerStateChanged && _dragHandle) {
        CGPoint point = [self layoutPointOfBodyPoint:[pan locationInView:_body]];
        NSUInteger index = [_item.textLayout characterIndexAtPoint:point];
        NSUInteger from = _pick.location, to = NSMaxRange(_pick);
        if (_dragHandle == 1) from = MIN(index, to - 1);
        else to = MAX(index, from + 1);
        _pick = NSMakeRange(from, to - from);
        _body.pickRange = _pick;
        [_body setNeedsDisplay];
        return;
    }
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        _dragHandle = 0;
        [self showPickMenu];
    }
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (_pick.length) {
        /* a tap in the selected words brings the menu back; anywhere else drops the selection */
        CGPoint inside = [self layoutPointOfBodyPoint:[tap locationInView:_body]];
        BOOL onWords = NO;
        for (NSValue *box in [_item.textLayout rectsForRange:_pick]) if (CGRectContainsPoint(CGRectInset(box.CGRectValue, -4, -4), inside)) onWords = YES;
        if (onWords) [self showPickMenu];
        else [self clearTextSelection];
        return;
    }
    if (_item.giftCard && CGRectContainsPoint(_item.bubbleFrame, [tap locationInView:self.contentView]) && [_delegate respondsToSelector:@selector(messageCellDidTapGift:)]) {
        [_delegate messageCellDidTapGift:self];
        return;
    }
    if (_item && _item.kind == NoshiChatItemPill && _item.message.service && CGRectContainsPoint(_item.bubbleFrame, [tap locationInView:self.contentView]) &&
        [_delegate respondsToSelector:@selector(messageCellDidTapService:)]) {
        [_delegate messageCellDidTapService:self];
        return;
    }
    if (!_item || _item.kind == NoshiChatItemPill) return;
    CGPoint point = [tap locationInView:self.contentView];
    if (_item.content == NoshiChatItemContentPoll && [_delegate respondsToSelector:@selector(messageCell:didTapPollAnswer:)]) {
        CGPoint inPoll = CGPointMake(point.x - _item.bubbleFrame.origin.x, point.y - _item.bubbleFrame.origin.y);
        if (_item.pollButtonTitle.length && CGRectContainsPoint(_item.pollButtonFrame, inPoll)) {
            [_delegate messageCell:self didTapPollAnswer:-1];
            return;
        }
        NSUInteger answer = [_item pollAnswerAtPoint:inPoll];
        if (answer != NSNotFound) {
            [_delegate messageCell:self didTapPollAnswer:(NSInteger)answer];
            return;
        }
    }
    if (!_reactions.hidden && CGRectContainsPoint(_reactions.frame, point)) return;
    if (_markupView && !_markupView.hidden && CGRectContainsPoint(_markupView.frame, point)) return;
    CGPoint inBody = [tap locationInView:_body];
    if (!_item.message.outgoing) inBody.x -= _body.tailWidth;
    NoshiMessage *message = _item.message;
    NSString *url = _item.textLayout ? [_item.textLayout linkAtPoint:CGPointMake(inBody.x - _item.textOrigin.x, inBody.y - _item.textOrigin.y)] : nil;
    if ([url isEqualToString:NoshiSpoilerTarget]) {
        message.spoilersRevealed = YES;
        _item.textLayout.spoilersRevealed = YES;
        [_body setNeedsDisplay];
        return;
    }
    if (url) {
        [_delegate messageCell:self didTapLink:url];
        return;
    }
    if (!_selecting && [_delegate respondsToSelector:@selector(messageCell:didTapCode:)]) {
        NoshiTextEntity *code = [_item.textLayout codeAtPoint:CGPointMake(inBody.x - _item.textOrigin.x, inBody.y - _item.textOrigin.y)];
        if (code) {
            noshi_entity spoilers[NOSHI_MESSAGE_ENTITIES_MAX];
            size_t count = 0;
            memset(spoilers, 0, sizeof(spoilers));
            for (NoshiTextEntity *entity in message.entities) {
                if (entity.style != NoshiTextStyleSpoiler) continue;
                if (count == NOSHI_MESSAGE_ENTITIES_MAX || entity.range.location > INT32_MAX || entity.range.length > INT32_MAX) return;
                spoilers[count].kind = NOSHI_ENTITY_SPOILER;
                spoilers[count].offset = (int32_t)entity.range.location;
                spoilers[count++].length = (int32_t)entity.range.length;
            }
            if (!message.spoilersRevealed && noshi_code_has_hidden_spoiler(code.range.location, code.range.length, spoilers, count)) {
                message.spoilersRevealed = YES;
                _item.textLayout.spoilersRevealed = YES;
                [_body setNeedsDisplay];
            } else [_delegate messageCell:self didTapCode:code];
            return;
        }
    }
    if (!_selecting && _item.textLayout && [_delegate respondsToSelector:@selector(messageCell:didToggleQuote:)]) {
        NSUInteger quote = [_item.textLayout foldableQuoteAtPoint:CGPointMake(inBody.x - _item.textOrigin.x, inBody.y - _item.textOrigin.y)];
        if (quote != NSNotFound) {
            [_delegate messageCell:self didToggleQuote:quote];
            return;
        }
    }
    if (_item.albumFrames.count) {
        CGPoint inBubble = [tap locationInView:self.contentView];
        inBubble.x -= _item.bubbleFrame.origin.x;
        inBubble.y -= _item.bubbleFrame.origin.y;
        NoshiMessage *picked = [_item albumMessageAtPoint:inBubble];
        if (picked) {
            [_tappedMedia release];
            _tappedMedia = [picked retain];
            [_delegate messageCellDidTapMedia:self];
            return;
        }
    }
    [_tappedMedia release];
    _tappedMedia = nil;
    if (!_selecting && _item.message.media.kind == NOSHI_PREVIEW_PAID && _item.message.messageId > 0 &&
        [_delegate respondsToSelector:@selector(messageCellDidTapPaid:)]) {
        [_delegate messageCellDidTapPaid:self];
        return;
    }
    if (!_selecting && _item.message.media.kind == NOSHI_PREVIEW_LOCATION && _item.message.media.location.valid &&
        CGRectContainsPoint(_map.frame,[tap locationInView:self.contentView])) {
        [_delegate messageCellDidTapMedia:self];
        return;
    }
    /* the first tap on a hidden picture shows it and nothing more; the cover does not exist until the first spoiler, and a nil cover reads as not hidden, which
       swallowed every tap on a picture, a sticker, a gif and a round video */
    if (_spoilerCover && !_spoilerCover.hidden && CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        _item.message.spoilersRevealed = YES;
        NoshiSpoilerCover *cover = _spoilerCover;
        NSUInteger token = _token;
        NoshiWeakReference *weak = _weak;
        [cover revealFromPoint:[tap locationInView:cover] done:^{
            NoshiMessageCell *cell = weak.target;
            if (!cell || token != cell->_token) return;
            cover.hidden = YES;
            if ([cell.delegate respondsToSelector:@selector(messageCellDidRevealSpoiler:)]) [cell.delegate messageCellDidRevealSpoiler:cell];
        }];
        return;
    }
    if (!_picture.hidden && _item.content == NoshiChatItemContentPicture &&
        _item.message.media.kind == NOSHI_PREVIEW_GIF &&
        CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        [self tappedGif];
        return;
    }
    if (!_picture.hidden && _item.content == NoshiChatItemContentPicture && [self uploading] && !_play.hidden &&
        CGRectContainsPoint(CGRectInset(_play.frame, -8, -8), [tap locationInView:self.contentView])) {
        [self cancelSending];
        return;
    }
    if (!_picture.hidden && _item.content == NoshiChatItemContentPicture && noshi_media_opens_viewer(_item.message.media.kind) &&
        CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        if (![self tappedMediaButton]) [_delegate messageCellDidTapMedia:self];
        return;
    }
    if (_item.kind == NoshiChatItemRound && CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        [self toggleRound];
        return;
    }
    /* a sticker of a pack opens the pack, as in the other clients; the animation of one that moves plays when it comes up, not on a tap */
    if (_item.kind == NoshiChatItemSticker && _item.message.media.stickerSetId && [_delegate respondsToSelector:@selector(messageCellDidTapSticker:)] &&
        CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        [_delegate messageCellDidTapSticker:self];
        return;
    }
    BOOL animatedKind = _item.kind == NoshiChatItemEmoji ||
        (_item.kind == NoshiChatItemSticker && (_item.message.media.stickerFormat == NOSHI_STICKER_ANIMATED || _item.message.media.stickerFormat == NOSHI_STICKER_VIDEO));
    if (animatedKind && CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        if (_lottie || _slots) {
            _emojiPlayed = YES;
            [self replayAnimation];
        } else {
            _replayRequested = YES;
            if (_item.kind == NoshiChatItemEmoji) [self loadEmojiAnimation];
            else [self loadLottieFile:_item.message.media.file];
        }
        return;
    }
    CGPoint inReply = _item.kind == NoshiChatItemBubble ? inBody : [tap locationInView:self.contentView];
    CGRect replyFrame = _item.kind == NoshiChatItemBubble ? _item.replyFrame : _replyPreview.frame;
    if (!CGRectIsEmpty(replyFrame) && CGRectContainsPoint(replyFrame, inReply)) {
        [_delegate messageCellDidTapReply:self];
        return;
    }
    /* the line "forwarded from" takes to the one who wrote it, or says that they hid their account */
    if (_item.kind == NoshiChatItemBubble && _item.forwardText.length && [_delegate respondsToSelector:@selector(messageCellDidTapForward:)]) {
        CGRect line = CGRectInset(CGRectMake(_item.forwardOrigin.x, _item.forwardOrigin.y, _item.forwardLayout.size.width, _item.forwardLayout.size.height), -8, -6);
        if (CGRectContainsPoint(line, inBody)) {
            [_delegate messageCellDidTapForward:self];
            return;
        }
    }
    if (_item.commentsText.length && CGRectContainsPoint(_item.commentsFrame, inBody)) {
        [_delegate messageCellDidTapComments:self];
        return;
    }
    if (message.outgoing && message.state == NoshiMessageStateFailed && CGRectContainsPoint(CGRectInset(CGRectMake(_item.timeOrigin.x, _item.timeOrigin.y, _item.timeSize.width, _item.timeSize.height), -10, -10), inBody)) {
        [_delegate messageCellDidTapFailed:self];
        return;
    }
    if (_item.content == NoshiChatItemContentFile && NoshiMessageIsViewOnce(message) && CGRectContainsPoint(_item.fileFrame, inBody)) {
        if ([_delegate respondsToSelector:@selector(messageCellDidTapViewOnce:)]) [_delegate messageCellDidTapViewOnce:self];
        return;
    }
    if (_item.content == NoshiChatItemContentFile && message.media.kind == NOSHI_PREVIEW_FILE && !_voiceAction.hidden && CGRectContainsPoint(_item.fileFrame, inBody)) {
        [self tappedFileButton];
        return;
    }
    if (_item.content == NoshiChatItemContentFile && (message.media.kind == NOSHI_PREVIEW_AUDIO || message.media.kind == NOSHI_PREVIEW_VOICE) &&
        CGRectContainsPoint(_item.fileFrame, inBody)) {
        NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
        BOOL current = [player isCurrentTrack:message.media] && (player.state == NoshiMusicStatePlaying || player.state == NoshiMusicStatePaused);
        if (message.media.kind == NOSHI_PREVIEW_VOICE && current) {
            CGRect wave = [_body waveRect];
            if (CGRectContainsPoint(CGRectInset([_body speedChipRect], -6, -6), inBody)) {
                [player cycleSpeed];
                return;
            }
            /* a tap in the bars jumps there; the play button and the time still pause */
            if (CGRectContainsPoint(wave, inBody) && wave.size.width > 0) {
                [player seekToFraction:(float)((inBody.x - wave.origin.x) / wave.size.width)];
                return;
            }
        }
        [_delegate messageCellDidTapAudio:self];
        return;
    }
    if ([_delegate respondsToSelector:@selector(messageCellDidTapBody:)]) [_delegate messageCellDidTapBody:self];
}

@end
