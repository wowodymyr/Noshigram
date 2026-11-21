#import <UIKit/UIKit.h>
#import "noshi_session.h"

/* the pictures the server draws one ordinary reaction with; around is nil for a reaction that has no short burst */
/* posted on the main thread when the catalog is in, so a screen builds the chips it already shows again with the server's icons */
extern NSString *const NoshiReactionArtworkDidLoadNotification;

@class NoshiMediaCache, NoshiLottieView;
@interface NoshiReactionArtwork : NSObject {
    NSString *_emoji;
    NoshiCustomEmojiDocument *_icon;
    NoshiCustomEmojiDocument *_appear;
    NoshiCustomEmojiDocument *_select;
    NoshiCustomEmojiDocument *_activate;
    NoshiCustomEmojiDocument *_effect;
    NoshiCustomEmojiDocument *_around;
}
@property (nonatomic, readonly, copy) NSString *emoji;
/* the still picture a chip and a menu show */
@property (nonatomic, readonly, retain) NoshiCustomEmojiDocument *icon;
/* lottie: the pop of the picker, the press, the reaction flying to the message, the large burst beside it, the short burst of a double tap */
@property (nonatomic, readonly, retain) NoshiCustomEmojiDocument *appear;
@property (nonatomic, readonly, retain) NoshiCustomEmojiDocument *select;
@property (nonatomic, readonly, retain) NoshiCustomEmojiDocument *activate;
@property (nonatomic, readonly, retain) NoshiCustomEmojiDocument *effect;
@property (nonatomic, readonly, retain) NoshiCustomEmojiDocument *around;

/* the art of an ordinary emoji reaction once the catalog is in, nil before and for an emoji the server does not draw */
+ (NoshiReactionArtwork *)artForEmoji:(NSString *)emoji;
/* replaces what is known with the catalog and teaches NoshiReaction the document of each still icon, so a chip draws it in the place of the emoji */
+ (void)setCatalog:(NSArray *)catalog;
/* tags of the views a reaction button carries: the label that stands in, and the still picture of the server that takes its place */
#define NOSHI_REACTION_LABEL_TAG 7300
#define NOSHI_REACTION_STILL_TAG 7301
/* the still picture the server keeps for a reaction, put in the button at its own size over the label that stands in until the picture is in hand. The label took the
   picture through the custom emoji path, which trims and rescales it, so after an animation it came back smaller and softer than the animation it followed.
   Returns nil when the server draws nothing for the reaction */
+ (UIImageView *)attachStillOfArtwork:(NoshiReactionArtwork *)artwork toButton:(UIButton *)button side:(CGFloat)side media:(NoshiMediaCache *)media;
/* the view that rests in the button once an animation over it has ended: the still picture when it is in, else the label */
+ (void)showRestingViewInButton:(UIButton *)button;
+ (BOOL)hasCatalog;
/* asks the server once (a call in flight or a catalog in hand is not asked for again), then loads the still icons so the chips of the screens draw them */
+ (void)loadWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;
/* a lottie view of one of the animations, ready to play, once its file is in hand; the completion runs on the main thread, with nil for a document that is not a lottie
   file, a file that cannot be fetched, or while reduced motion is on */
+ (void)animationViewForDocument:(NoshiCustomEmojiDocument *)document media:(NoshiMediaCache *)media completion:(void (^)(NoshiLottieView *view))completion;
- (id)initWithEmoji:(NSString *)emoji icon:(NoshiCustomEmojiDocument *)icon appear:(NoshiCustomEmojiDocument *)appear
            select:(NoshiCustomEmojiDocument *)select activate:(NoshiCustomEmojiDocument *)activate
            effect:(NoshiCustomEmojiDocument *)effect around:(NoshiCustomEmojiDocument *)around;
@end
