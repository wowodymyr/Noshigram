#import "noshi_now_playing.h"

#import <objc/message.h>

#import "noshi_audio_session.h"

static NSString *NoshiMediaKey(const char *name) {
    return NoshiAudioConstant(name);
}

/* one player owns the lock screen; keep its artwork across rate and position updates */
static UIImage *NoshiNowPlayingCover;
static id NoshiNowPlayingArtwork;

void NoshiNowPlayingShow(NSString *title, NSString *performer, UIImage *cover, NSTimeInterval position, NSTimeInterval duration, float rate) {
    Class centerClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!centerClass) return;
    id center = [centerClass performSelector:NSSelectorFromString(@"defaultCenter")];
    NSString *titleKey = NoshiMediaKey("MPMediaItemPropertyTitle"), *artistKey = NoshiMediaKey("MPMediaItemPropertyArtist");
    NSString *durationKey = NoshiMediaKey("MPMediaItemPropertyPlaybackDuration"), *elapsedKey = NoshiMediaKey("MPNowPlayingInfoPropertyElapsedPlaybackTime");
    NSString *rateKey = NoshiMediaKey("MPNowPlayingInfoPropertyPlaybackRate"), *artKey = NoshiMediaKey("MPMediaItemPropertyArtwork");
    if (!center || !titleKey) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (title) [info setObject:title forKey:titleKey];
    if (performer.length && artistKey) [info setObject:performer forKey:artistKey];
    if (duration > 0 && durationKey) [info setObject:[NSNumber numberWithDouble:duration] forKey:durationKey];
    if (elapsedKey) [info setObject:[NSNumber numberWithDouble:position] forKey:elapsedKey];
    if (rateKey) [info setObject:[NSNumber numberWithFloat:rate] forKey:rateKey];
    Class artworkClass = NSClassFromString(@"MPMediaItemArtwork");
    if (cover != NoshiNowPlayingCover) {
        [NoshiNowPlayingArtwork release];
        NoshiNowPlayingArtwork = nil;
        UIImage *nextCover = [cover retain];
        [NoshiNowPlayingCover release];
        NoshiNowPlayingCover = nextCover;
        SEL initializer = NSSelectorFromString(@"initWithImage:");
        if (cover && artKey && [artworkClass instancesRespondToSelector:initializer])
            NoshiNowPlayingArtwork = [[artworkClass alloc] performSelector:initializer withObject:cover];
    }
    if (NoshiNowPlayingArtwork && artKey) [info setObject:NoshiNowPlayingArtwork forKey:artKey];
    [center setValue:info forKey:@"nowPlayingInfo"];
}

void NoshiNowPlayingClear(void) {
    [NoshiNowPlayingArtwork release];
    NoshiNowPlayingArtwork = nil;
    [NoshiNowPlayingCover release];
    NoshiNowPlayingCover = nil;
    Class centerClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!centerClass) return;
    id center = [centerClass performSelector:NSSelectorFromString(@"defaultCenter")];
    [center setValue:nil forKey:@"nowPlayingInfo"];
}

/* before ios 7.1 an application is the one that plays for the lock screen and the tray of the multitasking bar only while a first responder takes the remote events: asking for them is
   not enough, and without a responder the system kept the Music app there, with its name and its icon, over the buttons of this one. a view of no size in the window is that responder.
   it never takes the focus from a text field, which would close the keyboard */
@interface NoshiRemoteResponder : UIView
@end

@implementation NoshiRemoteResponder
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    id<UIApplicationDelegate> delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(remoteControlReceivedWithEvent:)]) [(id)delegate remoteControlReceivedWithEvent:event];
}
@end

static NoshiRemoteResponder *NoshiRemoteResponderView;
static BOOL NoshiKeyboardUp;
static BOOL NoshiRemoteActive;

void NoshiRemoteControlsClaim(void) {
    if (!NoshiRemoteActive || NSClassFromString(@"MPRemoteCommandCenter") || NoshiKeyboardUp) return;
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    if (!NoshiRemoteResponderView) {
        NoshiRemoteResponderView = [[NoshiRemoteResponder alloc] initWithFrame:CGRectZero];
        /* a hidden view is refused as first responder on ios 6, so it stays visible and clear */
        NoshiRemoteResponderView.alpha = 0;
        NoshiRemoteResponderView.userInteractionEnabled = NO;
    }
    if (NoshiRemoteResponderView.superview != window) [window addSubview:NoshiRemoteResponderView];
    if (!NoshiRemoteResponderView.isFirstResponder && ![NoshiRemoteResponderView becomeFirstResponder]) NSLog(@"noshigram: the remote events found no responder");
}

static void NoshiWatchKeyboard(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIKeyboardDidShowNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { (void)note; NoshiKeyboardUp = YES; }];
        [center addObserverForName:UIKeyboardDidHideNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            (void)note;
            NoshiKeyboardUp = NO;
            /* the field that held the focus is gone, so the remote events have no responder again until it is taken back */
            NoshiRemoteControlsClaim();
        }];
    });
}

static void NoshiCommand(id center, NSString *name, id target, SEL action) {
    id command = [center valueForKey:name];
    if (!command || !action) return;
    /* the commands of next and previous song start switched off, and the buttons of the lock screen and the control center stay grey until they are on */
    [command setValue:[NSNumber numberWithBool:YES] forKey:@"enabled"];
    ((void (*)(id, SEL, id, SEL))objc_msgSend)(command, NSSelectorFromString(@"addTarget:action:"), target, action);
}

BOOL NoshiRemoteControlsActive(void) { return NoshiRemoteActive; }

static NSArray *NoshiCommandNames(void) {
    return [NSArray arrayWithObjects:@"playCommand", @"pauseCommand", @"togglePlayPauseCommand", @"nextTrackCommand", @"previousTrackCommand", nil];
}

static void NoshiRemoveCommandTargets(id center, id target) {
    for (NSString *name in NoshiCommandNames()) [[center valueForKey:name] performSelector:NSSelectorFromString(@"removeTarget:") withObject:target];
}

void NoshiRemoteControlsStart(id target, SEL play, SEL pause, SEL toggle, SEL next, SEL previous) {
    /* ios 8 lists the app in the control center only while it asks for the remote events, the commands alone are not enough */
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    NoshiRemoteActive = YES;
    Class commandClass = NSClassFromString(@"MPRemoteCommandCenter");
    if (commandClass) {
        id center = [commandClass performSelector:NSSelectorFromString(@"sharedCommandCenter")];
        /* targets are added once; adding the same one twice would run a command twice */
        NoshiRemoveCommandTargets(center, target);
        NoshiCommand(center, @"playCommand", target, play);
        NoshiCommand(center, @"pauseCommand", target, pause);
        NoshiCommand(center, @"togglePlayPauseCommand", target, toggle);
        NoshiCommand(center, @"nextTrackCommand", target, next);
        NoshiCommand(center, @"previousTrackCommand", target, previous);
        return;
    }
    /* before ios 7.1 the buttons come as events to the first responder, and the application delegate at the end of its chain */
    NoshiWatchKeyboard();
    NoshiRemoteControlsClaim();
}

void NoshiRemoteControlsStop(id target) {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    NoshiRemoteActive = NO;
    Class commandClass = NSClassFromString(@"MPRemoteCommandCenter");
    if (commandClass) {
        NoshiRemoveCommandTargets([commandClass performSelector:NSSelectorFromString(@"sharedCommandCenter")], target);
        return;
    }
    [NoshiRemoteResponderView resignFirstResponder];
    [NoshiRemoteResponderView removeFromSuperview];
}
