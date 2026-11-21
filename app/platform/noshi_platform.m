#import "noshi_platform.h"

#import <dlfcn.h>

#include "noshi_column.h"

NSString *const NoshiPadInterfaceKey = @"noshigram.developer.padInterface";

NSString *const NoshiPhoneInterfaceKey = @"noshigram.developer.phoneInterface";

BOOL NoshiIsPad(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:NoshiPhoneInterfaceKey]) return NO;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:NoshiPadInterfaceKey]) return YES;
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

CGFloat NoshiScreenScale(void) {
    UIScreen *screen = [UIScreen mainScreen];
    return [screen respondsToSelector:@selector(scale)] ? screen.scale : 1.0;
}

/* these properties are absent from the armv7 sdk, so they are read through key value coding */
static CGFloat NoshiGuideLength(UIViewController *controller, NSString *key) {
    if (![controller respondsToSelector:NSSelectorFromString(key)]) return 0;
    id guide = [controller valueForKey:key];
    return [[guide valueForKey:@"length"] doubleValue];
}

UIEdgeInsets NoshiSafeInsets(UIView *view) {
    if (![view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")]) return UIEdgeInsetsZero;
    return [[view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue];
}

void NoshiScrollViewOwnsInsets(UIScrollView *scroll) {
    if (![scroll respondsToSelector:NSSelectorFromString(@"setContentInsetAdjustmentBehavior:")]) return;
    /* UIScrollViewContentInsetAdjustmentNever; the constant is absent from the armv7 sdk */
    [scroll setValue:[NSNumber numberWithInteger:2] forKey:@"contentInsetAdjustmentBehavior"];
}

void NoshiTableUsesExactHeights(UITableView *table) {
    if (![table respondsToSelector:NSSelectorFromString(@"setEstimatedRowHeight:")]) return;
    [table setValue:[NSNumber numberWithDouble:0] forKey:@"estimatedRowHeight"];
    [table setValue:[NSNumber numberWithDouble:0] forKey:@"estimatedSectionHeaderHeight"];
    [table setValue:[NSNumber numberWithDouble:0] forKey:@"estimatedSectionFooterHeight"];
}

UIEdgeInsets NoshiLayoutInsets(UIViewController *controller) {
    UIView *view = controller.view;
    if ([view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")]) return NoshiSafeInsets(view);
    CGFloat top = NoshiGuideLength(controller, @"topLayoutGuide");
    UIWindow *window = view.window;
    if (window) {
        /* ios 5 has no guides, and ios 7 can pass the same status inset down nested containers */
        top = 0;
        if (![UIApplication sharedApplication].statusBarHidden) {
            CGRect status = [window convertRect:[UIApplication sharedApplication].statusBarFrame fromWindow:nil];
            CGRect overlap = CGRectIntersection(view.bounds, [view convertRect:status fromView:window]);
            if (!CGRectIsNull(overlap) && CGRectGetMinY(overlap) <= CGRectGetMinY(view.bounds)) top = overlap.size.height;
        }
        UINavigationController *navigation = controller.navigationController;
        if (navigation && !navigation.navigationBarHidden) {
            UINavigationBar *bar = navigation.navigationBar;
            CGRect overlap = CGRectIntersection(view.bounds, [view convertRect:bar.bounds fromView:bar]);
            if (!CGRectIsNull(overlap) && CGRectGetMinY(overlap) <= CGRectGetMinY(view.bounds) + top) {
                top = MAX(top, CGRectGetMaxY(overlap) - CGRectGetMinY(view.bounds));
            }
        }
    }
    return UIEdgeInsetsMake(top, 0, NoshiGuideLength(controller, @"bottomLayoutGuide"), 0);
}

CGRect NoshiContentColumn(CGSize size, UIEdgeInsets insets, CGFloat maxWidth) {
    noshi_column column;
    if (noshi_column_place(size.width, insets.left, insets.right, NoshiIsPad() ? maxWidth : 0, &column) != NOSHI_OK) {
        return CGRectMake(0, 0, size.width, size.height);
    }
    return CGRectMake((CGFloat)column.x, 0, (CGFloat)column.width, size.height);
}

BOOL NoshiReduceMotionEnabled(void) {
    BOOL (*enabled)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "UIAccessibilityIsReduceMotionEnabled");
    return enabled ? enabled() : NO;
}

NSString *NoshiReduceMotionChangedNotification(void) {
    NSString **name = (NSString **)dlsym(RTLD_DEFAULT, "UIAccessibilityReduceMotionStatusDidChangeNotification");
    return name ? *name : nil;
}

BOOL NoshiAllowsOrientation(UIInterfaceOrientation orientation) {
    return NoshiIsPad() || orientation != UIInterfaceOrientationPortraitUpsideDown;
}

NSUInteger NoshiOrientationMask(void) {
    return NoshiIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}


static BOOL NoshiDefaultsPending;

static void NoshiDefaultsSaveNow(void) {
    NoshiDefaultsPending = NO;
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the user defaults were not saved");
}

void NoshiDefaultsSaveSoon(void) {
    static BOOL watching;
    if (!watching) {
        watching = YES;
        void (^flush)(NSNotification *) = ^(NSNotification *note) {
            (void)note;
            if (NoshiDefaultsPending) NoshiDefaultsSaveNow();
        };
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:flush];
        [center addObserverForName:UIApplicationWillTerminateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:flush];
    }
    if (NoshiDefaultsPending) return;
    NoshiDefaultsPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (NoshiDefaultsPending) NoshiDefaultsSaveNow();
    });
}

UIView *NoshiOverlayHost(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top.view ? top.view : window;
}

CGFloat NoshiStatusBarHeight(void) {
    CGRect frame = [UIApplication sharedApplication].statusBarFrame;
    return [UIApplication sharedApplication].statusBarHidden ? 0 : MIN(frame.size.width, frame.size.height);
}


/* ---- the status bar of the screens that cover the whole display ----
   each of them used to remember the state it found and put that back, so a screen that opened over another that had hidden the bar restored "hidden" for
   good, and the story camera never gave the bar back. the owners are counted instead: the bar is hidden while any owner is on screen, and shown when the
   last one lets go. an owner calls Show from dealloc too, so one that left without its disappear call cannot hold the bar */
static NSMutableSet *NoshiStatusOwners(void) {
    static NSMutableSet *owners;
    if (!owners) owners = [[NSMutableSet alloc] init];
    return owners;
}

static void NoshiStatusBarApply(BOOL hidden, UIStatusBarAnimation animation) {
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)] && application.statusBarHidden != hidden)
        [application setStatusBarHidden:hidden withAnimation:animation];
}

void NoshiStatusBarHide(id owner, UIStatusBarAnimation animation) {
    if (!owner) return;
    [NoshiStatusOwners() addObject:[NSValue valueWithNonretainedObject:owner]];
    NoshiStatusBarApply(YES, animation);
}

void NoshiStatusBarShow(id owner, UIStatusBarAnimation animation) {
    if (!owner) return;
    NSMutableSet *owners = NoshiStatusOwners();
    [owners removeObject:[NSValue valueWithNonretainedObject:owner]];
    if (!owners.count) NoshiStatusBarApply(NO, animation);
}

void NoshiStatusBarSettle(void) {
    NSMutableSet *owners = NoshiStatusOwners();
    for (NSValue *held in [[owners copy] autorelease]) {
        id owner = [held nonretainedObjectValue];
        /* an owner whose screen is gone from the window no longer needs the bar hidden */
        BOOL shown = [owner isKindOfClass:[UIViewController class]] && [(UIViewController *)owner isViewLoaded] && [(UIViewController *)owner view].window;
        if (!shown) [owners removeObject:held];
    }
    if (!owners.count) NoshiStatusBarApply(NO, UIStatusBarAnimationNone);
}


/* ---- the black under a viewer ----
   a viewer that lets its picture go translucent while it is pulled away shows whatever is under it, which for a screen over the whole display is the color of
   the window, light in the light themes. the window is black while a viewer is up, and the color comes back when the last one is gone */
static NSUInteger NoshiBlackHolders;
static UIColor *NoshiBlackSaved;

void NoshiWindowBlackHold(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    if (NoshiBlackHolders++ == 0) {
        NoshiBlackSaved = [window.backgroundColor retain];
        window.backgroundColor = [UIColor blackColor];
    }
}

void NoshiWindowBlackRelease(void) {
    if (!NoshiBlackHolders) return;
    if (--NoshiBlackHolders == 0) {
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (window && NoshiBlackSaved) window.backgroundColor = NoshiBlackSaved;
        [NoshiBlackSaved release];
        NoshiBlackSaved = nil;
    }
}
