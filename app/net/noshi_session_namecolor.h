#import <Foundation/Foundation.h>

#import "noshi_session.h"

/* the color of the person's own name, from help.getPeerColors and account.updateColor */
@interface NoshiSession (NameColor)

/* the list of the colors the server offers, stored for the chats to draw with; the completion gets it as the dictionaries NoshiServerNameColors gives */
- (void)loadNameColors:(void (^)(NSArray *colors, NSString *errorName))completion;
- (void)setNameColorId:(NSInteger)colorId completion:(void (^)(NSString *errorName))completion;

@end
