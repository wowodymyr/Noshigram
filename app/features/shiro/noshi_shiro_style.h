#import <UIKit/UIKit.h>

/* the Shiro screens follow Material 3 Expressive: tonal surfaces from one raspberry seed, Rubik for every text,
   large rounded shapes, springy motion */

UIColor *NoshiShiroColorSurface(void);
/* the plate of the account */
UIColor *NoshiShiroColorSurfaceContainer(void);
/* the resting face of the power shape and the fill of quiet buttons */
UIColor *NoshiShiroColorSurfaceHighest(void);
UIColor *NoshiShiroColorOnSurface(void);
UIColor *NoshiShiroColorOnSurfaceVariant(void);
UIColor *NoshiShiroColorOutline(void);
UIColor *NoshiShiroColorPrimary(void);
UIColor *NoshiShiroColorOnPrimary(void);
UIColor *NoshiShiroColorPrimaryContainer(void);
UIColor *NoshiShiroColorOnPrimaryContainer(void);
UIColor *NoshiShiroColorSecondaryContainer(void);
UIColor *NoshiShiroColorOnSecondaryContainer(void);
UIColor *NoshiShiroColorError(void);
UIColor *NoshiShiroColorErrorContainer(void);
UIColor *NoshiShiroColorOnErrorContainer(void);

/* the colors one lap of the shimmering title passes through, the first one repeated at the end is left to the caller */
NSArray *NoshiShiroShimmerColors(void);

/* Rubik at the weight of the Material type scale; the system face stands in where the font file is missing from the bundle */
UIFont *NoshiShiroFontDisplay(CGFloat size);
UIFont *NoshiShiroFontBody(CGFloat size, BOOL medium);

/* the size of "1.2 MB" style text for a byte count */
NSString *NoshiShiroByteText(unsigned long long bytes);
