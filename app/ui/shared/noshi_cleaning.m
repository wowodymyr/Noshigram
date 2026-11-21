#import "noshi_cleaning.h"

#import "noshi_platform.h"
#import "noshi_theme_busy_view.h"

#define STEP_SECONDS 1.0
#define DONE_SECONDS 0.9

@interface NoshiCleaningStep () {
@public
    NSString *name;
    void (^work)(void (^finished)(BOOL));
}
@end

@implementation NoshiCleaningStep

+ (NoshiCleaningStep *)stepNamed:(NSString *)name work:(void (^)(void))work {
    NoshiCleaningStep *step = [[[NoshiCleaningStep alloc] init] autorelease];
    step->name = [name copy];
    step->work = [^(void (^finished)(BOOL)) { if (work) work(); finished(YES); } copy];
    return step;
}

+ (NoshiCleaningStep *)stepNamed:(NSString *)name asyncWork:(void (^)(void (^)(BOOL)))work {
    NoshiCleaningStep *step = [[[NoshiCleaningStep alloc] init] autorelease];
    step->name = [name copy];
    step->work = [work copy];
    return step;
}

- (void)dealloc {
    [name release];
    [work release];
    [super dealloc];
}

@end

/* the view is kept for the next cleaning, with its animation parsed */
static NoshiThemeBusyView *NoshiCleaningView;
static BOOL NoshiCleaningRunning;

static void NoshiCleaningFinish(void (^done)(void)) {
    NoshiThemeBusyView *view = NoshiCleaningView;
    BOOL still = NoshiReduceMotionEnabled();
    [UIView animateWithDuration:still ? 0 : 0.3 animations:^{ view.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [view stopAnimating];
        [view removeFromSuperview];
        NoshiCleaningRunning = NO;
        if (done) done();
    }];
}

static void NoshiCleaningStepAt(NSArray *steps, NSUInteger index, BOOL success, void (^done)(void)) {
    if (index >= steps.count) {
        NoshiCleaningView.text = NSLocalizedString(success ? @"cache.cleaned" : @"cache.clean.failed", nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DONE_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NoshiCleaningFinish(done); });
        return;
    }
    NoshiCleaningStep *step = [steps objectAtIndex:index];
    NoshiCleaningView.text = [NSString stringWithFormat:NSLocalizedString(@"cache.cleaning", nil), step->name];
    void (^next)(BOOL) = ^(BOOL ok) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(STEP_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NoshiCleaningStepAt(steps, index + 1, success && ok, done); });
    };
    if (step->work) step->work(next);
    else next(NO);
}

void NoshiRunCleaning(NSArray *steps, void (^done)(void)) {
    UIView *window = NoshiOverlayHost();
    if (NoshiCleaningRunning) return;
    NoshiCleaningRunning = YES;
    if (window) {
        if (!NoshiCleaningView) NoshiCleaningView = [[NoshiThemeBusyView alloc] initWithFrame:window.bounds animation:@"clear_cache"];
        NoshiCleaningView.frame = window.bounds;
        NoshiCleaningView.alpha = NoshiReduceMotionEnabled() ? 1 : 0;
        [window addSubview:NoshiCleaningView];
        [NoshiCleaningView startAnimating];
        [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.22 animations:^{ NoshiCleaningView.alpha = 1; }];
    }
    NSArray *kept = [steps copy];
    void (^finished)(void) = [done copy];
    NoshiCleaningStepAt(kept, 0, YES, ^{
        if (finished) finished();
        [finished release];
        [kept release];
    });
}
