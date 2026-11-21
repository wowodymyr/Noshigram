#import "noshi_saved_media_controller.h"
#import "noshi_group_tabs_view.h"
#import "noshi_chat_controller.h"
#import "noshi_media_viewer.h"
#import "noshi_platform.h"
#import "noshi_user_profile_controller.h"
#import "noshi_music_list_controller.h"
#import "noshi_music_pill.h"
#import "noshi_session_profile.h"
#import "noshi_weak_reference.h"

@interface NoshiSavedMediaController () <NoshiGroupTabsDelegate, UIScrollViewDelegate> {
    NoshiDialog *_dialog;
    UIScrollView *_scroll;
    NoshiGroupTabsView *_tabs;
    NoshiMusicPill *_music;
    NoshiMedia *_savedTrack;
    NSUInteger _musicGeneration;
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiSavedMediaController
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(@"chats.saved", nil);
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    _music.contentHandler = nil;
    [_music release];
    [_savedTrack release];
    _tabs.delegate = nil;
    [_tabs release];
    _scroll.delegate = nil;
    [_scroll release];
    [_dialog release];
    [super dealloc];
}
- (void)buildBodyInView:(UIView *)root {
    _scroll = [[UIScrollView alloc] init];
    NoshiScrollViewOwnsInsets(_scroll);
    _scroll.delegate = self;
    [root addSubview:_scroll];
    _music = [[NoshiMusicPill alloc] init];
    _music.media = self.media;
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    NoshiWeakReference *weak = _weak;
    _music.contentHandler = ^{ [[(NoshiSavedMediaController *)weak.target view] setNeedsLayout]; };
    [_scroll addSubview:_music];
    _tabs = [[NoshiGroupTabsView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media forUser:YES];
    _tabs.delegate = self;
    [_scroll addSubview:_tabs];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    (void)scrollView;
    [_tabs hostDidScroll];
}
- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat top = 0;
    if (_music.hasContent) {
        CGFloat pillWidth = [_music widthWithin:MAX(0, body.size.width - 28)];
        _music.frame = CGRectMake(floor((body.size.width - pillWidth) / 2), 12, pillWidth, [NoshiMusicPill height]);
        top = CGRectGetMaxY(_music.frame) + 12;
    }
    CGFloat height = [_tabs heightForWidth:body.size.width];
    _tabs.frame = CGRectMake(0, top, body.size.width, height);
    _scroll.contentSize = CGSizeMake(body.size.width, top + height);
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* returning from our playlist refreshes the first song after it was removed */
    NSUInteger generation = ++_musicGeneration;
    NoshiWeakReference *weak = _weak;
    [self.session loadFullUserOfDialog:_dialog completion:^(NoshiFullUser *user, NSString *errorName) {
        NoshiSavedMediaController *screen = weak.target;
        if (!screen || generation != screen->_musicGeneration) return;
        if (!user) {
            NSLog(@"noshigram: saved messages profile music did not load: %@", errorName);
            return;
        }
        [screen->_savedTrack release];
        screen->_savedTrack = [user.music retain];
        screen->_music.savedTrack = user.music;
        [screen.view setNeedsLayout];
    }];
}
- (void)openMusic {
    NoshiMusicListController *list = [[[NoshiMusicListController alloc] initWithSession:self.session dialog:_dialog first:_savedTrack
                                                                                              avatars:self.avatars media:self.media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}
- (void)groupTabsDidResize:(NoshiGroupTabsView *)tabs {
    (void)tabs;
    [self.view setNeedsLayout];
}
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenPerson:(NoshiPerson *)person {
    (void)tabs;
    NoshiUserProfileController *profile = [[[NoshiUserProfileController alloc] initWithSession:self.session dialog:[NoshiDialog dialogWithPerson:person] avatars:self.avatars media:self.media stickers:nil] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMessage:(NoshiMessage *)message {
    (void)tabs;
    NSArray *stack = self.navigationController.viewControllers;
    for (UIViewController *screen in [stack reverseObjectEnumerator]) {
        if (![screen isKindOfClass:[NoshiChatController class]]) continue;
        NoshiChatController *chat = (NoshiChatController *)screen;
        if (![chat showsDialog:_dialog]) continue;
        [self.navigationController popToViewController:chat animated:YES];
        [chat jumpToMessageId:message.messageId];
        return;
    }
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars
        media:self.media stickers:nil] autorelease];
    chat.startMessageId = message.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}
- (void)groupTabs:(NoshiGroupTabsView *)tabs didOpenMedia:(NoshiMessage *)message among:(NSArray *)messages {
    (void)tabs;
    NoshiMediaViewer *viewer = [[[NoshiMediaViewer alloc] initWithMessages:messages selected:message media:self.media
                                                                     senderNames:nil chatTitle:NSLocalizedString(@"chats.saved", nil)] autorelease];
    NoshiWeakReference *weakScreen = [NoshiWeakReference referenceTo:self];
    viewer.showInChatHandler = ^(NoshiMessage *shown) {
        id me = weakScreen.target;
        if (me) [me groupTabs:nil didOpenMessage:shown];
    };
    [self presentViewController:viewer animated:YES completion:nil];
}
@end
