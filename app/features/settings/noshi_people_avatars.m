#import "noshi_people_avatars.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_weak_reference.h"

#define SIDE 48.0

@interface NoshiPeopleAvatars () {
    NoshiAvatarCache *_cache;
    NSMutableDictionary *_images;
    NSMutableSet *_asked;
    NoshiWeakReference *_weak;
    void (^_changed)(void);
    BOOL _changePending;
}
@end

@implementation NoshiPeopleAvatars

- (id)initWithCache:(NoshiAvatarCache *)cache changed:(void (^)(void))changed {
    self = [super init];
    if (!self) return nil;
    _cache = [cache retain];
    _images = [[NSMutableDictionary alloc] init];
    _asked = [[NSMutableSet alloc] init];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _changed = [changed copy];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fireChanged) object:nil];
    [_weak clear];
    [_weak release];
    [_cache release];
    [_images release];
    [_asked release];
    [_changed release];
    [super dealloc];
}

/* the pictures land one by one, and each used to rebuild the whole list at once: with a few hundred chats that is as many rebuilds of as many rows, which held the main thread
   for seconds on a slow phone (the page of forwarding hung for it). the landings of a moment are told as one */
- (void)fireChanged {
    _changePending = NO;
    if (_changed) _changed();
}

- (void)invalidate {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fireChanged) object:nil];
    _changePending = NO;
    [_weak clear];
    [_changed release];
    _changed = nil;
}

/* the colors and initials of the avatar view, drawn once into a picture */
static UIImage *NoshiPlaceholderImage(NSString *initials, NSUInteger seed, BOOL deleted) {
    NoshiAvatarView *view = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(0, 0, SIDE, SIDE)] autorelease];
    view.circular = YES;
    view.initials = initials;
    view.seed = seed;
    view.deleted = deleted;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(SIDE, SIDE), NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the avatar view owns the look of a photo with see-through parts: it stands on the gradient of the person, and a bare picture drawn into a clear
   circle shows the white of the table behind it */
static UIImage *NoshiRoundImage(UIImage *photo, NSUInteger seed) {
    NoshiAvatarView *view = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(0, 0, SIDE, SIDE)] autorelease];
    view.circular = YES;
    view.seed = seed;
    [view showImage:photo];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(SIDE, SIDE), NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)useStoredPhoto:(UIImage *)photo forKey:(NSString *)key seed:(NSUInteger)seed {
    if (!photo || [_asked containsObject:key]) return;
    [_asked addObject:key];
    [_images setObject:NoshiRoundImage(photo, seed) forKey:key];
}

- (UIImage *)imageForKey:(NSString *)key initials:(NSString *)initials seed:(NSUInteger)seed deleted:(BOOL)deleted photo:(NoshiPhoto *)photo {
    UIImage *image = [_images objectForKey:key];
    if (!image) {
        image = NoshiPlaceholderImage(initials, seed, deleted);
        [_images setObject:image forKey:key];
    }
    /* a synchronous cache hit can replace this image while the caller is still building rows */
    image = [[image retain] autorelease];
    if (photo && _cache && ![_asked containsObject:key]) {
        [_asked addObject:key];
        NoshiWeakReference *weak = _weak;
        __block BOOL inCall = YES;
        [_cache loadImageForPhoto:photo completion:^(UIImage *loaded) {
            NoshiPeopleAvatars *me = weak.target;
            if (!me || !loaded) return;
            [me->_images setObject:NoshiRoundImage(loaded, seed) forKey:key];
            if (!inCall && me->_changed && !me->_changePending) {
                me->_changePending = YES;
                [me performSelector:@selector(fireChanged) withObject:nil afterDelay:0.25];
            }
        }];
        inCall = NO;
        UIImage *current = [_images objectForKey:key];
        if (current) image = current;
    }
    return image;
}

@end
