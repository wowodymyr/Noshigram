#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_session_channels.h"

@class NoshiGroupTabsView;

@protocol NoshiGroupTabsDelegate <NSObject>
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenPerson:(NoshiPerson *)person;
/* a file or link was tapped: the chat opens at this message */
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMessage:(NoshiMessage *)message;
/* a photo or video of the media tab was tapped: the viewer opens on it, with the pictures and videos of the tab as its pages, not the chat. messages are in the
   order of the tab and all have a file */
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMedia:(NoshiMessage *)message among:(NSArray *)messages;
/* the height of the content changed, so the header that holds the view has to grow */
- (void)groupTabsDidResize:(NoshiGroupTabsView *)tabs;
@optional
/* a group of the groups-in-common tab was tapped: its chat opens */
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenDialog:(NoshiDialog *)dialog;
/* a tab was chosen; for a user's tabs the gifts tab (selectedTab 0) has no content of its own, the screen shows the gifts */
- (void)groupTabsDidChooseTab:(NoshiGroupTabsView *)tabs;
@end

/* the lists under a group: its members with their roles at the right, and the photos and videos, files and links
   of its chat; main thread only */
@interface NoshiGroupTabsView : UIView

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
              forUser:(BOOL)forUser;
/* the same for a channel whose list of members the account may not see (it is not an administrator, and the server answers a broadcast channel's members only to those): the tab is left out */
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
              forUser:(BOOL)forUser hidesMembers:(BOOL)hidesMembers;
/* 0 is Members, or Gifts for a user */
@property (nonatomic, readonly) NSUInteger selectedTab;

@property (nonatomic, assign) id<NoshiGroupTabsDelegate> delegate;

/* the members list starts again from the first page, after somebody was added */
- (void)reloadMembers;
/* a user's tabs get the groups in common once the profile says there are some, as a last tab; nothing changes for a count of zero or for a group's tabs */
- (void)setCommonChatsCount:(NSInteger)count;
- (CGFloat)heightForWidth:(CGFloat)width;
/* the screen's list scrolled: the bar of the selection stays below the top bar while the list runs under it */
- (void)hostDidScroll;

@end
