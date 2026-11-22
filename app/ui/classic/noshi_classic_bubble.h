#import <UIKit/UIKit.h>

/* the flat speech bubble of the classic chat, cut from the old Messages pictures and colored with the accent. a bubble with a tail has 6 points
   of tail on the side it leans to (the left for the ones that came in, the right for the ones sent) and the body fills the rest; one without a tail
   is the plain bubble. the image stretches with its corners and tail kept, and is made once for each color it is asked for */
#define NOSHI_CLASSIC_BUBBLE_TAIL 6.0
/* the radius of the corners of the bubble pictures, which a photo or a video that runs to the edge of the bubble takes for its own outer corners */
#define NOSHI_CLASSIC_BUBBLE_CORNER 12.0

UIImage *NoshiClassicBubbleImage(BOOL outgoing, BOOL tail);
