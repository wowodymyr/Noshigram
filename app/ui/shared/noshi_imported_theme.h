#import <UIKit/UIKit.h>
#include <stdint.h>

NSString *NoshiImportedThemeCheck(NSURL *url, BOOL *dark, NSString **name);
NSString *NoshiImportedThemeInstall(NSURL *url, BOOL dark);
NSString *NoshiImportedThemeBeginPreview(NSURL *url);
void NoshiImportedThemeUseBuiltin(BOOL dark);
BOOL NoshiImportedThemeSelected(BOOL dark);
void NoshiImportedThemeReload(BOOL dark);
UIColor *NoshiImportedThemeColor(const char *key);
NSString *NoshiImportedThemeWallpaper(void);
NSUInteger NoshiImportedThemeWallpaperGradient(uint32_t colors[4], int *angle);
