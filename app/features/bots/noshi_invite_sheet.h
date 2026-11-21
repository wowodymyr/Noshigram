#import <UIKit/UIKit.h>

@class NoshiRemoteFile;
@class NoshiMediaCache;

@interface NoshiInviteSheet : UIView
+ (void)showInView:(UIView *)host title:(NSString *)title subtitle:(NSString *)subtitle about:(NSString *)about
             photo:(NoshiRemoteFile *)photo media:(NoshiMediaCache *)media requestNeeded:(BOOL)requestNeeded joinTitle:(NSString *)joinTitle join:(void (^)(void))join;
@end
