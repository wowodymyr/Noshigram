#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_photo.h"
#import "noshi_symbol.h"

@class NoshiTabBar;

@protocol NoshiTabBarDelegate <NSObject>
- (void)tabBar:(NoshiTabBar *)tabBar didSelectIndex:(NSInteger)index;
@optional
/* a tap on the tab that is already selected */
- (void)tabBar:(NoshiTabBar *)tabBar didReselectIndex:(NSInteger)index;
/* a finger held on a tab; frame is the tab in the coordinates of the bar */
- (void)tabBar:(NoshiTabBar *)tabBar didLongPressIndex:(NSInteger)index frame:(CGRect)frame;
@end

/* the bottom bar of the signed in app: a symbol over a caption per tab, an optional red count on a tab,
   an opaque plate with a hairline on top */
@interface NoshiTabBar : UIView {
    id<NoshiTabBarDelegate> _delegate;
    NSInteger _selectedIndex;
    CGRect _itemArea;
}

@property (nonatomic, assign) id<NoshiTabBarDelegate> delegate;
@property (nonatomic, assign) NSInteger selectedIndex;
/* the strip of the bar the tabs share, in the bar's own coordinates; the plate and the hairline keep the full
   width */
@property (nonatomic, assign) CGRect itemArea;

/* titles are localized strings, symbols are NoshiSymbol values wrapped in NSNumber, or NSNull for a tab that
   shows the profile photo instead of a symbol; both arrays have one entry per tab */
- (id)initWithTitles:(NSArray *)titles symbols:(NSArray *)symbols;
- (void)setBadge:(NSInteger)count forIndex:(NSInteger)index;
/* another caption and symbol for a tab (a plugin retitled it); a tab that wears the profile photo keeps its photo and takes the caption only */
- (void)setTitle:(NSString *)title symbol:(NSNumber *)symbol forIndex:(NSInteger)index;
/* what the avatar tab shows: the photo once the cache has it, the initials on a color until then */
- (void)setAvatarInitials:(NSString *)initials seed:(NSUInteger)seed photo:(NoshiPhoto *)photo cache:(NoshiAvatarCache *)cache
                 forIndex:(NSInteger)index;

/* the bar itself, without the bottom safe area it sits above */
+ (CGFloat)barHeight;

@end
