#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_message.h"
#import "noshi_symbol.h"
@class NoshiAvatarCache;

/* one entry of the menu: a title, a glyph and the number the owner knows the action by */
@interface NoshiMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NoshiSymbol symbol;
@property (nonatomic, assign) NSUInteger tag;
@property (nonatomic, assign) BOOL destructive;
+ (NoshiMenuItem *)itemWithTitle:(NSString *)title symbol:(NoshiSymbol)symbol tag:(NSUInteger)tag destructive:(BOOL)destructive;
@end

/* the menu of a message, laid out as exteraGram lays it out */
@interface NoshiMessageMenu : UIView

/* the text rows, and the glyph buttons of the bottom row */
@property (nonatomic, copy) NSArray *rows;
@property (nonatomic, copy) NSArray *icons;
/* an entry was picked; the menu has left by the time this runs */
@property (nonatomic, copy) void (^pickHandler)(NSUInteger tag);
/* a reaction of the pill was tapped, or the arrow after them */
@property (nonatomic, copy) void (^reactionHandler)(NoshiReaction *reaction);
@property (nonatomic, copy) void (^moreReactionsHandler)(void);
/* the menu was closed without a pick */
@property (nonatomic, copy) void (^dismissHandler)(void);
@property (nonatomic, copy) void (^headerHandler)(void);
/* the first of those who read the message (NoshiPerson), shown as small pictures at the right end of the header; the cache gives their photos */
- (void)setHeaderPeople:(NSArray *)people cache:(NoshiAvatarCache *)cache;
/* the line under the header that counts the reactions, tapped to see who made them; nil text takes it away, and the people are the first of them (NoshiPerson) */
@property (nonatomic, copy) void (^reactorsHandler)(void);
- (void)setReactorsText:(NSString *)text;
- (void)setReactorsPeople:(NSArray *)people cache:(NoshiAvatarCache *)cache;
/* the cache the pill takes the lottie of each reaction from; without it the reactions stay still pictures */
@property (nonatomic, retain) NoshiMediaCache *media;

/* the line at the top of the card, with a read mark when read is set; nil text takes the line away */
- (void)setHeaderText:(NSString *)text read:(BOOL)read;
/* the pill; nil or an empty list takes it away */
- (void)setReactions:(NSArray *)reactions;

/* bubble is the part of the message that can be seen, in the coordinates of host; snapshot is a picture of the
   message to keep lit at snapshotFrame, shown only inside clip, nil for none */
- (void)showInView:(UIView *)host bubble:(CGRect)bubble outgoing:(BOOL)outgoing snapshot:(UIImage *)snapshot snapshotFrame:(CGRect)snapshotFrame clip:(CGRect)clip;
- (void)dismiss;

@end
