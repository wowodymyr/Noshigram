#import "noshi_mutual_icon.h"

#import "noshi_alert.h"

/* one arrow: the shaft and the head, from tail to tip along x, at height y, pointing right when direction is 1 and left when it is -1 */
static void NoshiAddArrow(UIBezierPath *path, CGFloat tail, CGFloat tip, CGFloat y, CGFloat head) {
    CGFloat direction = tip > tail ? 1 : -1;
    [path moveToPoint:CGPointMake(tail, y)];
    [path addLineToPoint:CGPointMake(tip, y)];
    [path moveToPoint:CGPointMake(tip - direction * head, y - head)];
    [path addLineToPoint:CGPointMake(tip, y)];
    [path addLineToPoint:CGPointMake(tip - direction * head, y + head)];
}

UIImage *NoshiMutualIconImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineWidth = MAX(1.5, side / 12);
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    CGFloat margin = side * 0.14, head = side * 0.15;
    NoshiAddArrow(path, margin, side - margin, side * 0.36, head);
    NoshiAddArrow(path, side - margin, margin, side * 0.64, head);
    [color setStroke];
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

void NoshiShowMutualNotice(void) {
    NoshiShowNotice(NSLocalizedString(@"contact.mutual", nil), NSLocalizedString(@"contact.mutual.text", nil));
}
