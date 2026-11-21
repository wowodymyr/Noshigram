#import "noshi_dialog.h"
#import "noshi_session.h"
#import "noshi_star_gift.h"

/* the gifts Noshigram puts on the profile of a person it names, as the lead developer's own and as his gifts to others: they are made here and not by the server, so everybody who runs
   the app sees it, and it stands before every gift of the profile, pinned. its sender is @sqmrak, with the name and the picture the server has for him.
   empty for every other account, for a chat that is not a person, and for a folder of gifts.
   they are made as the unique gifts of the server are: a number of their own that counts from 1, a model, a symbol and a backdrop, the backdrop drawn in soft
   expressive shapes (NoshiGiftBackdropView.expressive) in colors of their own */
NSArray *NoshiCustomGiftsForDialog(NoshiDialog *owner);

/* "#001": the number of a gift of the app, in the three digits it is written with */
NSString *NoshiCustomGiftNumberText(int32_t number);

/* whether the profile gets the gift and the sender is not known yet: the feed asks for him before it builds the gift */
BOOL NoshiCustomGiftNeedsSender(NoshiDialog *owner);
/* loads the sender by id, once, and keeps the answer for the run; done runs on the main thread, also when he could not be had (the gift then names him
   without a picture) */
void NoshiCustomGiftLoadSender(NoshiSession *session, void (^done)(void));
