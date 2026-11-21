#import "noshi_topic_icon.h"

#import "noshi_custom_emoji.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"

/* a forum offers a handful of icon colors, so the hashes drawn so far stay kept */
static NSMutableDictionary *NoshiHashImages(void) {
    static NSMutableDictionary *images;
    if (!images) images = [[NSMutableDictionary alloc] init];
    return images;
}

static UIImage *NoshiHashImage(int32_t rgb) {
    NSNumber *key = [NSNumber numberWithInt:rgb];
    UIImage *image = [NoshiHashImages() objectForKey:key];
    if (image) return image;
    UIColor *color = rgb ? [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1]
                         : NoshiColorAccent();
    CGSize size = CGSizeMake(NOSHI_TOPIC_ICON_SIDE, NOSHI_TOPIC_ICON_SIDE);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color set];
    NSString *hash = @"#";
    UIFont *font = NoshiFontBold(NOSHI_TOPIC_ICON_SIDE);
    CGSize fit = NoshiStringSize(hash, font);
    NoshiDrawStringIn(hash, font, CGRectMake(0, (size.height - fit.height) / 2, size.width, fit.height), NoshiStringClip, NoshiTextAlignmentCenter);
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [NoshiHashImages() setObject:image forKey:key];
    return image;
}

UIImage *NoshiTopicIconImageOf(long long emoji, int32_t rgb) {
    if (emoji) {
        /* drawn 48 points wide, so the still at full size and not the half-size frame of an animated emoji, which was stretched to twice its pixels */
        UIImage *picture = [NoshiCustomEmoji stillImageForDocument:emoji];
        if (picture) return picture;
    }
    return NoshiHashImage(rgb);
}

UIImage *NoshiTopicIconImage(NoshiDialog *topic) {
    return NoshiTopicIconImageOf(topic.topicIconEmoji, topic.topicIconColor);
}
