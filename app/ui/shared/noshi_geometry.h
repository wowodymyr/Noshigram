#import <CoreGraphics/CoreGraphics.h>

#import "noshi_welcome.h"

static inline CGRect NoshiCGRect(noshi_rect rect) {
    return CGRectMake((CGFloat)rect.x, (CGFloat)rect.y, (CGFloat)rect.width, (CGFloat)rect.height);
}

static inline CGRect NoshiCGRectOffset(noshi_rect rect, CGFloat dx, CGFloat dy) {
    return CGRectMake((CGFloat)rect.x + dx, (CGFloat)rect.y + dy, (CGFloat)rect.width, (CGFloat)rect.height);
}
