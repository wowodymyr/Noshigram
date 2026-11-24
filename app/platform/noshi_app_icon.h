#import <UIKit/UIKit.h>

/* the one icon of the app, as the splash and the launch images draw it */

/* the picture the splash shows */
UIImage *NoshiSplashIconImage(void);
/* the launch images carry the icon on the color of the screen of the theme, so the system's first picture is the splash the app then shows;
   drawn again at launch and on a change of the theme, where the bundle can be written */
void NoshiAppIconRefreshLaunchImages(void);
