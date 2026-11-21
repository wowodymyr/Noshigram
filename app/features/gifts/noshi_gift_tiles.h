#import "noshi_gift_grid_view.h"
#import "noshi_gift_screen.h"
#import "noshi_star_gift.h"
#import "noshi_story.h"

/* the tile of a gift on a profile; mine marks the gifts hidden from the owner's own profile */
NoshiGiftTileInfo *NoshiTileForSavedGift(NoshiSavedGift *saved, BOOL mine);
/* the tile of a gift for sale */
NoshiGiftTileInfo *NoshiTileForCatalogGift(NoshiStarGift *gift);
/* the tile of a story: its picture or the thumbnail of its video, the day and how many saw it */
NoshiGiftTileInfo *NoshiTileForStory(NoshiStory *story);
