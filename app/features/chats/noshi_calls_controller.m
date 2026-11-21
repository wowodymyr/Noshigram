#import "noshi_developers.h"
#import "noshi_calls_controller.h"

#import "noshi_chat_controller.h"
#import "noshi_person_cell.h"
#import "noshi_session_calllog.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_weak_reference.h"

@interface NoshiCallsController () {
    NSArray *_entries;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickerLibrary;
}
@end

@implementation NoshiCallsController

@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(NoshiSession *)session {
    self = [super initWithSession:session];
    if (!self) return nil;
    self.heading = NSLocalizedString(@"tab.calls", nil);
    return self;
}

- (void)dealloc {
    [_entries release];
    [_media release];
    [_stickerLibrary release];
    [super dealloc];
}

/* a call can end with the app on screen, and the log is asked again each time the tab comes back */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)loadItemsWithCompletion:(NoshiListCompletion)completion {
    [self.session loadCallLog:completion];
}

- (void)didReceiveItems:(NSArray *)items {
    [_entries release];
    _entries = [items retain];
}

- (NSInteger)itemCount {
    return (NSInteger)_entries.count;
}

- (NSString *)emptyText {
    return NSLocalizedString(@"calls.empty", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_entries.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [NoshiPersonCell rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"call";
    NoshiPersonCell *cell = (NoshiPersonCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    NoshiCallLogEntry *entry = [_entries objectAtIndex:(NSUInteger)indexPath.row];
    BOOL bad = entry.missed && !entry.outgoing;
    cell.developer = NoshiMarksOfId(entry.userId);
    [cell configureWithName:entry.name initials:entry.initials seed:(NSUInteger)(entry.userId % 1000003)
                   subtitle:[entry summaryText] subtitleColor:bad ? NoshiColorBadgeRed() : nil
                   trailing:NoshiListTimeText(entry.date) symbol:entry.video ? NoshiSymbolVideoCallMenu : NoshiSymbolPhone showsSymbol:YES
                  nameColor:nil photo:entry.photo avatars:self.avatars];
    cell.avatarDeleted = entry.deleted;
    return cell;
}

- (void)openChatOf:(NoshiCallLogEntry *)entry {
    NoshiDialog *dialog = [entry dialog];
    if (!dialog) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:dialog avatars:self.avatars
                                                                           media:_media stickers:_stickerLibrary] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NoshiCallLogEntry *entry = [_entries objectAtIndex:(NSUInteger)indexPath.row];
    if (![entry dialog]) return;
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"calls.callback", nil), NSLocalizedString(@"calls.openchat", nil), nil];
    [NoshiSheet presentInView:self.view title:entry.name message:nil options:options destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil)
                        handler:^(NSUInteger index) {
        NoshiCallsController *me = weak.target;
        if (!me) return;
        if (index == 0) [me.session startCallToDialog:[entry dialog]];
        else [me openChatOf:entry];
    }];
}

@end
