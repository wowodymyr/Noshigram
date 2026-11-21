#import <UIKit/UIKit.h>

#import "noshi_dialog.h"

/* the side in points of the picture NoshiTopicIconImage gives */
#define NOSHI_TOPIC_ICON_SIDE 48.0

/* the icon of a forum topic: its custom emoji once the picture is in memory, otherwise a hash in the topic's color */
UIImage *NoshiTopicIconImage(NoshiDialog *topic);

/* the same for an icon named by its parts, as the chat list names the topic of the last message of a forum */
UIImage *NoshiTopicIconImageOf(long long emoji, int32_t rgb);
