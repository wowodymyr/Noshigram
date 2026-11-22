#import <UIKit/UIKit.h>

void NoshiReleaseCheckStart(UIWindow *window);
/* the latest release, or an error; the completion runs on the main thread */
void NoshiFetchLatestRelease(void (^completion)(NSDictionary *release, NSString *error));
