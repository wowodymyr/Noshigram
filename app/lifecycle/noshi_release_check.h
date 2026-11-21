#import <UIKit/UIKit.h>

void NoshiReleaseCheckStart(UIWindow *window);
/* the notice of a new release with made up notes and no files to install, over the host; for the developer settings */
void NoshiShowReleasePreview(UIView *host);
/* the latest release, or an error; the completion runs on the main thread */
void NoshiFetchLatestRelease(void (^completion)(NSDictionary *release, NSString *error));
