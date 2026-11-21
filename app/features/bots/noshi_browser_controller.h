#import <UIKit/UIKit.h>

/* an address the in-app browser opens: http and https */
BOOL NoshiIsWebURL(NSURL *url);
void NoshiPresentBrowser(NSURL *url, UIViewController *host);
