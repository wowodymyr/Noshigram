#import <UIKit/UIKit.h>

/* the Material shapes an avatar or a round button can take. the first is the rounded square whose corner the person sets in percent, the second a circle; the others are
   closed outlines made of many short segments, drawn into the square the box holds */
typedef enum {
    NoshiShapeRounded = 0,
    NoshiShapeCircle,
    NoshiShapeCookie,
    NoshiShapeSunny,
    NoshiShapeClover,
    NoshiShapeFlower,
    NoshiShapePentagon,
    NoshiShapeGem,
    NoshiShapeBurst,
    NoshiShapeCount
} NoshiShape;

/* whether the outline is one of the polylines below, and not a circle or a rounded square */
BOOL NoshiShapeIsOutline(NoshiShape shape);
/* the outline of an outline shape, centered in box and as large as the shorter side lets it be; a rounded square or a circle gives the rounded rectangle of cornerPercent
   (0 to 100) of the shorter side, for the callers that have no corner of their own */
UIBezierPath *NoshiShapePath(NoshiShape shape, CGRect box, NSInteger cornerPercent);
/* the length of the outline, for a ring that is dashed along it */
CGFloat NoshiShapePathLength(NoshiShape shape, CGRect box);

/* cuts a layer of side by side points to a shape: an outline shape by a mask, anything else by the corner radius of cornerPercent (a circle is 100); a layer that had a mask
   of an earlier shape loses it */
void NoshiApplyShapeToLayer(CALayer *layer, NoshiShape shape, CGFloat side, NSInteger cornerPercent);
