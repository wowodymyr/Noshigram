/* the developer builds (make NOSHI_DEV=1) save a picture of the screen to Caches/noshigram-screen.png when the darwin notification
   com.noshigram.app.screen is posted, so the look can be checked on a phone over ssh; other builds have none of it */

#ifdef NOSHI_DEV

#import <UIKit/UIKit.h>
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
}

#else

typedef int noshi_dev_screen_unused;

#endif
