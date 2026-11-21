#import "noshi_community_badge.h"

#import "noshi_symbol.h"
#import "noshi_theme.h"

UIImage *NoshiCommunityBadgeImage(void) {
    static UIImage *badge;
    if (badge) return badge;
    CGFloat side = NOSHI_COMMUNITY_BADGE_SIDE;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    /* a ring in the screen color keeps the badge apart from the avatar under it */
    [NoshiColorScreen() set];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    [NoshiColorAccent() set];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2, 2, side - 4, side - 4)] fill];
    CGFloat arrow = side * 0.7;
    [NoshiSymbolImage(NoshiSymbolArrowDown, arrow, [UIColor whiteColor]) drawAtPoint:CGPointMake((side - arrow) / 2, (side - arrow) / 2)];
    badge = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return badge;
}
