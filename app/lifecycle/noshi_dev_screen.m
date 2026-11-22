/* the developer builds (make NOSHI_DEV=1) save a picture of the screen to Caches/noshigram-screen.png when the darwin notification
   com.noshigram.app.screen is posted, the tree of views to Caches/noshigram-views.txt on com.noshigram.app.views, and show a made up in-app banner on com.noshigram.app.banner, so the look can be checked on a
   phone over ssh; other builds have none of it */

#ifdef NOSHI_DEV

#import <UIKit/UIKit.h>

#import "noshi_inapp_banner.h"
#include <dlfcn.h>
#include <notify.h>

__attribute__((constructor)) static void NoshiDevScreenInstall(void) {
    int token = 0;
    notify_register_dispatch("com.noshigram.app.screen", &token, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        /* private and missing from the stubs of the sdk, so it is looked up in uikit when asked for */
        CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
        CGImageRef screen = grab ? grab() : NULL;
        if (!screen) {
            NSLog(@"noshigram: dev screen: no picture");
            return;
        }
        UIImage *image = [UIImage imageWithCGImage:screen];
        CGImageRelease(screen);
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
        NSString *path = [caches stringByAppendingPathComponent:@"noshigram-screen.png"];
        if (![UIImagePNGRepresentation(image) writeToFile:path atomically:YES]) NSLog(@"noshigram: dev screen: %@ was not written", path);
    });
    /* the tree of views of the key window, with the frames and colors uikit prints, to Caches/noshigram-views.txt */
    int viewsToken = 0;
    notify_register_dispatch("com.noshigram.app.views", &viewsToken, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        SEL describe = NSSelectorFromString(@"recursiveDescription");
        NSString *tree = [window respondsToSelector:describe] ? [window performSelector:describe] : nil;
        /* the text fields with what they draw their words in, which the tree leaves out */
        NSMutableString *fields = [NSMutableString stringWithString:tree ? tree : @""];
        NSMutableArray *queue = [NSMutableArray arrayWithObject:window];
        while (queue.count) {
            UIView *view = [queue objectAtIndex:0];
            [queue removeObjectAtIndex:0];
            [queue addObjectsFromArray:view.subviews];
            if (![view isKindOfClass:[UITextField class]]) continue;
            UITextField *field = (UITextField *)view;
            [fields appendFormat:@"\nfield %p text '%@' color %@ font %@ typing %@ attributed %@\n", field, field.text, field.textColor, field.font, field.typingAttributes, field.attributedText];
        }
        tree = fields;
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
        NSString *path = [caches stringByAppendingPathComponent:@"noshigram-views.txt"];
        if (![tree writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) NSLog(@"noshigram: dev views: %@ was not written", path);
    });
    int bannerToken = 0;
    notify_register_dispatch("com.noshigram.app.banner", &bannerToken, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        [NoshiInAppBanner showTitle:@"Pavel Durov" body:@"Did you see the new banner? It looks just like the one of the old app." dialog:nil avatars:nil tap:nil];
    });
}

#else

typedef int noshi_dev_screen_unused;

#endif
