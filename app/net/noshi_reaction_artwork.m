#import "noshi_reaction_artwork.h"

#import "noshi_custom_emoji.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_image_decoder.h"
#import "noshi_lottie_view.h"
#import "noshi_platform.h"
#import "noshi_media_cache.h"
#import "noshi_message.h"

NSString *const NoshiReactionArtworkDidLoadNotification = @"NoshiReactionArtworkDidLoad";

static NSMutableDictionary *sArt;

@implementation NoshiReactionArtwork

@synthesize emoji = _emoji;
@synthesize icon = _icon;
@synthesize appear = _appear;
@synthesize select = _select;
@synthesize activate = _activate;
@synthesize effect = _effect;
@synthesize around = _around;

- (id)initWithEmoji:(NSString *)emoji icon:(NoshiCustomEmojiDocument *)icon appear:(NoshiCustomEmojiDocument *)appear
            select:(NoshiCustomEmojiDocument *)select activate:(NoshiCustomEmojiDocument *)activate
            effect:(NoshiCustomEmojiDocument *)effect around:(NoshiCustomEmojiDocument *)around {
    self = [super init];
    if (!self) return nil;
    _emoji = [emoji copy];
    _icon = [icon retain];
    _appear = [appear retain];
    _select = [select retain];
    _activate = [activate retain];
    _effect = [effect retain];
    _around = [around retain];
    return self;
}

- (void)dealloc {
    [_emoji release];
    [_icon release];
    [_appear release];
    [_select release];
    [_activate release];
    [_effect release];
    [_around release];
    [super dealloc];
}

+ (NoshiReactionArtwork *)artForEmoji:(NSString *)emoji {
    return emoji ? [sArt objectForKey:emoji] : nil;
}

+ (BOOL)hasCatalog {
    return sArt != nil;
}

+ (void)setCatalog:(NSArray *)catalog {
    NSMutableDictionary *next = [[NSMutableDictionary alloc] initWithCapacity:catalog.count];
    NSMutableDictionary *icons = [NSMutableDictionary dictionaryWithCapacity:catalog.count];
    for (NoshiReactionArtwork *art in catalog) {
        [next setObject:art forKey:art.emoji];
        [icons setObject:art.emoji forKey:[NSNumber numberWithLongLong:art.icon.documentId]];
    }
    [sArt release];
    sArt = next;
    [NoshiReaction rememberCustomTexts:icons];
}

+ (UIImageView *)attachStillOfArtwork:(NoshiReactionArtwork *)artwork toButton:(UIButton *)button side:(CGFloat)side media:(NoshiMediaCache *)media {
    /* the android client rests on the first frame of the select animation: the flat static icon of the server is a plainer picture than the animation that came before it */
    NoshiCustomEmojiDocument *resting = artwork.select.file ? artwork.select : artwork.icon;
    if (!resting.file || !media) return nil;
    UIImageView *still = [[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, side, side)] autorelease];
    still.tag = NOSHI_REACTION_STILL_TAG;
    still.contentMode = UIViewContentModeScaleAspectFit;
    still.userInteractionEnabled = NO;
    still.hidden = YES;
    still.center = CGPointMake(button.bounds.size.width / 2, button.bounds.size.height / 2);
    [button addSubview:still];
    /* the same side as the picture of the custom emoji path, so the cache of the images holds one decode for both */
    [media loadImageForFile:resting.file maxSide:[NoshiCustomEmoji pictureSide] completion:^(UIImage *image) {
        if (!image || !still.superview) return;
        still.image = image;
        BOOL animating = NO;
        for (UIView *view in button.subviews) if ([view isKindOfClass:[NoshiLottieView class]] && !view.hidden) animating = YES;
        still.hidden = animating;
        [button viewWithTag:NOSHI_REACTION_LABEL_TAG].hidden = YES;
    }];
    return still;
}

+ (void)showRestingViewInButton:(UIButton *)button {
    UIImageView *still = (UIImageView *)[button viewWithTag:NOSHI_REACTION_STILL_TAG];
    if (still.image) {
        still.hidden = NO;
        [button viewWithTag:NOSHI_REACTION_LABEL_TAG].hidden = YES;
    } else {
        [button viewWithTag:NOSHI_REACTION_LABEL_TAG].hidden = NO;
    }
}

+ (void)animationViewForDocument:(NoshiCustomEmojiDocument *)document media:(NoshiMediaCache *)media completion:(void (^)(NoshiLottieView *))completion {
    void (^done)(NoshiLottieView *) = [completion copy];
    if (!document || document.format != NOSHI_STICKER_ANIMATED || !document.file || !media || NoshiReduceMotionEnabled()) {
        done(nil);
        [done release];
        return;
    }
    NSString *key = document.file.key;
    [media loadDataForFile:document.file completion:^(NSData *data) {
        NoshiLottieView *view = nil;
        if (data && NoshiFileFormatOfData(data) == NoshiFileFormatGzip) view = [[[NoshiLottieView alloc] initWithPackedData:data key:key] autorelease];
        else NSLog(@"noshigram: reaction animation %lld is not a lottie file", document.documentId);
        done(view);
        [done release];
    }];
}

+ (void)loadWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media {
    static BOOL loading;
    if (sArt || loading || !session || !media) return;
    loading = YES;
    [session loadReactionArt:^(NSArray *art, NSString *errorName) {
        loading = NO;
        if (!art) {
            NSLog(@"noshigram: reaction art not loaded: %@", errorName);
            return;
        }
        [NoshiReactionArtwork setCatalog:art];
        NSMutableArray *icons = [NSMutableArray arrayWithCapacity:art.count];
        for (NoshiReactionArtwork *item in art) [icons addObject:item.icon];
        [NoshiCustomEmojiLoader loadPicturesOfDocuments:icons media:media picture:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiReactionArtworkDidLoadNotification object:nil];
    }];
}

@end
