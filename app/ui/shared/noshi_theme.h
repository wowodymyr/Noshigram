#import <UIKit/UIKit.h>

/* middle of the welcome gradient, for the window behind it during rotation */
UIColor *NoshiColorBackdrop(void);
/* the signed in screens come in a light and a dark palette; the screens before the login are always light,
   so the app delegate picks the palette each time it builds a root screen and colors are read at build time */
extern NSString *const NoshiThemeDidChangeNotification;
/* the optional key of its userInfo: an NSValue with the point in window coordinates the change of colors spreads from, which the screens that ask for a change give
   as the spot that was touched */
extern NSString *const NoshiThemeOriginKey;
BOOL NoshiClassicThemeAvailable(void);
/* developer switch that offers the classic theme on every ios, not only on 10 and older */
extern NSString *const NoshiClassicAnywhereKey;
BOOL NoshiThemeStoredClassic(void);
void NoshiThemeStoreClassic(BOOL classic);
BOOL NoshiThemeIsClassic(void);
BOOL NoshiThemeStoredDark(void);
void NoshiThemeStoreDark(BOOL dark);
BOOL NoshiThemeIsDark(void);
void NoshiThemeApply(BOOL dark);
/* the status bar style of a tone: light content on dark, black content on light */
UIStatusBarStyle NoshiStatusBarStyle(BOOL dark);
void NoshiThemeApplyStored(void);
/* a number that changes whenever the palette does (the dark and the light theme, the style, a hue of one's own, an imported theme): a cache of anything drawn in the colors of the theme
   keeps it in its key, or compares it, so nothing made before the change is shown after it */
NSUInteger NoshiThemeRevision(void);

/* a hue (degrees), a saturation and a brightness (0 to 1, of the accent; 1 is the accent of the palette, 0 is black) chosen by the person; while none is stored the palette is the purple of the app.
   Storing is silent: the caller posts NoshiThemeDidChangeNotification */
/* a color stored before the brightness existed reads as brightness 1 */
BOOL NoshiThemeStoredCustomTint(float *hue, float *saturation, float *brightness);
void NoshiThemeStoreCustomTint(float hue, float saturation, float brightness);
/* the accent of the light palette for such a pair, for a swatch that shows it before it is stored */
UIColor *NoshiThemeCustomTintColor(float hue, float saturation, float brightness);
/* a color of the palette of the app, or any other color built from fixed numbers, turned the same way; other colors than RGB come back as they are */
UIColor *NoshiThemeTinted(UIColor *color);
/* a color of a palette with a seed hue of its own (the Shiro screens), moved to the accent of the app: the seed hue goes to the hue of the accent, the saturation
   follows a color of your own, a grey accent makes the palette grey. With no color of your own stored the color comes back as it is */
UIColor *NoshiThemeFollowAccent(UIColor *color, CGFloat seedHue);
/* hue in degrees, saturation and value from 0 to 1 */
void NoshiRGBToHSV(CGFloat red, CGFloat green, CGFloat blue, CGFloat *hue, CGFloat *saturation, CGFloat *value);
void NoshiHSVToRGB(CGFloat hue, CGFloat saturation, CGFloat value, CGFloat *red, CGFloat *green, CGFloat *blue);

/* the screen, the fields and idle chips on it, cards and the tab bar, and the line between rows */
UIColor *NoshiColorScreen(void);
UIColor *NoshiColorField(void);
UIColor *NoshiColorCard(void);
UIColor *NoshiColorBar(void);
UIColor *NoshiColorHairline(void);
UIColor *NoshiColorAccent(void);
/* a color given as 0xRRGGBB, opaque */
UIColor *NoshiColorOfRGB(uint32_t rgb);
UIColor *NoshiColorAccentDark(void);
UIColor *NoshiColorTitle(void);
UIColor *NoshiColorMessage(void);
UIColor *NoshiColorDotOff(void);
/* secondary text on the lilac screens, and the quieter shade of it for muted chats and idle tabs */
UIColor *NoshiColorSecondary(void);
UIColor *NoshiColorMuted(void);
UIColor *NoshiColorBadgeRed(void);
/* the pale paper behind a QR code, white turned toward the hue of the chat color; dark modules still read on it */
UIColor *NoshiColorQrPaper(void);
/* chat bubbles: ours in the accent family, theirs on the card color, and the capsule behind dates and times */
UIColor *NoshiColorChatBackground(void);
UIColor *NoshiColorBubbleText(BOOL outgoing);
UIColor *NoshiColorBubbleLink(BOOL outgoing);
UIColor *NoshiColorBubbleLinkText(BOOL outgoing);
UIColor *NoshiColorBubbleMeta(BOOL outgoing);
/* the classic bubble as the old Messages drew it: a vertical gradient from top to bottom and an outline, none of them
   transparent so the wallpaper never shows through */
void NoshiClassicBubbleColors(BOOL outgoing, UIColor **top, UIColor **bottom, UIColor **outline);
/* the colors a theme gives a chat, for the preview of a theme that is not on screen; the style and the tone are
   switched for the moment of the call and put back, so the colors come from the same code that paints the real
   chat */
void NoshiThemePreviewColors(BOOL classic, BOOL dark, UIColor **incoming, UIColor **outgoing, UIColor **incomingText, UIColor **outgoingText);
UIColor *NoshiColorBubbleOut(void);
UIColor *NoshiColorBubbleIn(void);
UIColor *NoshiColorBubbleCapsule(void);

/* san Francisco on ios 9 and later; before that the bundled Inter, which sets the same way */
UIFont *NoshiFontRegular(CGFloat size);
UIFont *NoshiFontMedium(CGFloat size);
UIFont *NoshiFontSemibold(CGFloat size);
UIFont *NoshiFontBold(CGFloat size);
/* the size of the whole interface, in percent of the designed one. Screens read it when they are built, so a change is followed by the same rebuild of the main
   screens that a theme change makes (post NoshiThemeDidChangeNotification once the person has let go of the slider). The fonts of the NoshiFont and Shiro
   helpers follow it, and so do the sizes of the rows on the chat list */
#define NOSHI_INTERFACE_SCALE_MIN 85
#define NOSHI_INTERFACE_SCALE_MAX 125
CGFloat NoshiInterfaceScale(void);
NSInteger NoshiInterfaceScaleStored(void);
void NoshiInterfaceScaleStore(NSInteger percent);
/* the face the user picked changed: the faces already made are dropped, and the screens ask again when they are built */
void NoshiFontsDidChange(void);

/* the ios 5 UITextAlignment values and the ios 6 NSTextAlignment ones are the same numbers on iOS */
#define NoshiTextAlignmentCenter 1
#define NoshiTextAlignmentLeft 0
#define NoshiTextAlignmentRight 2

/* the color that is share (0 to 1) of the way from base to tint, solid whatever the alphas of the two; the plate of a quote is made of the bubble and the
   color of its author this way, so nothing behind the bubble shows through it */
UIColor *NoshiMixedColor(UIColor *base, UIColor *tint, CGFloat share);
