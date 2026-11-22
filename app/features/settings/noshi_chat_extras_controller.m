#import "noshi_chat_extras_controller.h"

#import "noshi_chat_preview_view.h"
#import "noshi_chat_settings.h"
#import "noshi_custom_emoji.h"
#import "noshi_name_color_controller.h"
#import "noshi_quick_reaction_controller.h"
#import "noshi_person.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#include "noshi_reactions.h"

@interface NoshiChatExtrasController () {
    NoshiSession *_session;
    NoshiMediaCache *_reactionMedia;
    NoshiWeakReference *_weak;
    /* the account itself, loaded for the name color row */
    NoshiPerson *_me;
    /* the demo dialog at the top; it redraws itself when a setting under it changes */
    NoshiChatPreviewView *_preview;
}
@end

@implementation NoshiChatExtrasController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.noshigram.chats", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiCustomEmojiDidLoadNotification object:nil];
    [_weak clear];
    [_weak release];
    [_session release];
    [_reactionMedia release];
    [_me release];
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(quickReactionPictureLoaded:) name:NoshiCustomEmojiDidLoadNotification object:nil];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    _reactionMedia = [[NoshiMediaCache alloc] initWithSession:_session directory:[[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"media"]];
    [self rebuild];
    [self loadMe];
}

- (void)quickReactionPictureLoaded:(NSNotification *)notification {
    if ([notification.object longLongValue] == noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String)) [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NoshiLoadQuickReactionPicture(_session, _reactionMedia, nil);
    if (self.isViewLoaded) [self rebuild];
}

/* the page stays up when the theme changes; its rows are made again in the new colors */
- (void)themeDidChange {
    /* the dialog reads its colors when it is made */
    [_preview release];
    _preview = nil;
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiChatExtrasController alloc] initWithSession:_session] autorelease];
}

- (void)loadMe {
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiChatExtrasController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"noshigram: the account did not load for the chat settings: %@", errorName);
            return;
        }
        [me->_me release];
        me->_me = [[items objectAtIndex:0] retain];
        [me rebuild];
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self lookSection]];
    /* the color of the name needs the account, which the screen waits for */
    if (_me) {
        NoshiSettingsRow *color = [NoshiSettingsRow rowWithSymbol:NoshiSymbolPerson tone:NoshiSettingsTonePurple title:NSLocalizedString(@"chatset.namecolor", nil)
                                                             subtitle:nil value:_me.name tap:^{
            NoshiChatExtrasController *me = weak.target;
            if (!me || !me->_me) return;
            NoshiNameColorController *colors = [[[NoshiNameColorController alloc] initWithSession:me->_session person:me->_me] autorelease];
            colors.changedHandler = ^(NSInteger colorId) { (void)colorId; [(NoshiChatExtrasController *)weak.target loadMe]; };
            [me.navigationController pushViewController:colors animated:YES];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:color]]];
    }
    [sections addObject:[self mediaSection]];
    [sections addObject:[self premiumElementsSection]];
    [sections addObject:[self messagesSection]];
    [sections addObject:[self menuSection]];
    [sections addObject:[self confirmSection]];
    self.sections = sections;
    [self reloadSettings];
}

#pragma mark sections

static NoshiSettingsRow *NoshiFlagRow(NSString *titleKey, NSString *infoKey, NoshiChatFlag flag) {
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil
                                               on:NoshiChatFlagGet(flag) toggle:^(BOOL on) {
        NoshiChatFlagSet(flag, on);
        /* the demo dialog shows some of these, so it hears of every change */
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    }];
}


/* what the demo dialog at the top shows and what moves it: the size and the shape of stickers, the time on them, and the quotes of replies */
- (NoshiSettingsSection *)lookSection {
    NoshiWeakReference *weak = _weak;
    /* the classic table has no row that is a view of the owner's, so there the dialog is left out */
    NoshiChatPreviewView *preview = _preview;
    NSMutableArray *rows = [NSMutableArray array];
    if (preview) [rows addObject:[NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }]];
    [rows addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.stickersize", nil) format:@"%.0f%%" value:(float)NoshiChatStickerScale()
                                                   minimum:NOSHI_STICKER_SCALE_MIN maximum:NOSHI_STICKER_SCALE_MAX change:^(float value) {
        [(NoshiChatExtrasController *)weak.target stickerScaleMoved:value];
    }]];
    [rows addObject:NoshiFlagRow(@"chatset.hidestickertime", nil, NoshiChatFlagHideStickerTime)];
    static NSString *const shapes[] = {@"chatset.shape.none", @"chatset.shape.rounded", @"chatset.shape.bubble"};
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.stickershape", nil) value:NSLocalizedString(shapes[NoshiChatStickerShape()], nil) tap:^{
        NoshiChatExtrasController *me = weak.target;
        if (!me) return;
        NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(shapes[0], nil), NSLocalizedString(shapes[1], nil), NSLocalizedString(shapes[2], nil), nil];
        NoshiSettingsChoose(me, NSLocalizedString(@"chatset.stickershape", nil), options, ^(NSUInteger index) {
            NoshiChatSetStickerShape((NoshiStickerShape)index);
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
            [(NoshiChatExtrasController *)weak.target rebuild];
        });
    }]];
    [rows addObject:NoshiFlagRow(@"chatset.replybackground", nil, NoshiChatFlagReplyBackground)];
    return [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:rows];
}

- (NoshiSettingsSection *)premiumElementsSection {
    NSArray *rows = [NSArray arrayWithObjects:
        NoshiFlagRow(@"chatset.premium.status", nil, NoshiChatFlagShowMessageEmojiStatus),
        NoshiFlagRow(@"chatset.premium.replyemoji", nil, NoshiChatFlagShowReplyCustomEmoji),
        NoshiFlagRow(@"chatset.replycolors", @"chatset.replycolors.info", NoshiChatFlagReplyColors), nil];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.premium.header", nil) footer:nil rows:rows];
}

/* playback beyond the original: the step of the seek, what pauses a voice or a round message when the app goes down, and the camera and the sound of videos */
- (NoshiSettingsSection *)mediaSection {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.seek", nil)
                                               value:[NSString stringWithFormat:NSLocalizedString(@"chatset.seek.value", nil), (int)NoshiChatSeekSeconds()] tap:^{
        NoshiChatExtrasController *me = weak.target;
        if (!me) return;
        NSArray *options = [NSArray arrayWithObjects:@"5", @"10", @"15", @"30", nil];
        NoshiSettingsChoose(me, NSLocalizedString(@"chatset.seek", nil), options, ^(NSUInteger index) {
            NoshiChatSetSeekSeconds([[options objectAtIndex:index] integerValue]);
            [(NoshiChatExtrasController *)weak.target rebuild];
        });
    }]];
    [rows addObject:NoshiFlagRow(@"chatset.pausevoice", nil, NoshiChatFlagPauseVoiceOnMinimize)];
    [rows addObject:NoshiFlagRow(@"chatset.pauseround", nil, NoshiChatFlagPauseRoundOnMinimize)];
    [rows addObject:NoshiFlagRow(@"chatset.noautonext", nil, NoshiChatFlagNoAutoNextVoice)];
    [rows addObject:NoshiFlagRow(@"chatset.unmutevolume", @"chatset.unmutevolume.info", NoshiChatFlagUnmuteWithVolume)];
    [rows addObject:NoshiFlagRow(@"chatset.alwayshd", @"chatset.alwayshd.info", NoshiChatFlagAlwaysHD)];
    [rows addObject:NoshiFlagRow(@"chatset.hidecameratile", nil, NoshiChatFlagHideCameraTile)];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.media.header", nil) footer:nil rows:rows];
}

/* what a double tap does is a choice of ten, kept apart for the messages of others and our own */
- (NoshiSettingsRow *)doubleTapRowOutgoing:(BOOL)outgoing {
    static NSString *const keys[NoshiDoubleTapCount] = {
        @"chatset.dt.none", @"chatset.dt.reaction", @"chatset.dt.picker", @"chatset.dt.translate", @"chatset.dt.reply",
        @"chatset.dt.forward", @"chatset.dt.save", @"chatset.dt.repeat", @"chatset.dt.edit", @"chatset.dt.delete"};
    NoshiWeakReference *weak = _weak;
    NSString *title = NSLocalizedString(outgoing ? @"chatset.doubletap.out" : @"chatset.doubletap.in", nil);
    return [NoshiSettingsRow rowWithTitle:title value:NSLocalizedString(keys[NoshiChatDoubleTap(outgoing)], nil) tap:^{
        NoshiChatExtrasController *me = weak.target;
        if (!me) return;
        NSMutableArray *options = [NSMutableArray array];
        /* editing is only for our own messages */
        for (int action = 0; action < NoshiDoubleTapCount; ++action) {
            if (action == NoshiDoubleTapEdit && !outgoing) continue;
            [options addObject:NSLocalizedString(keys[action], nil)];
        }
        NoshiSettingsChoose(me, title, options, ^(NSUInteger index) {
            int action = (int)index;
            if (!outgoing && action >= NoshiDoubleTapEdit) ++action;
            NoshiChatSetDoubleTap(outgoing, (NoshiDoubleTapAction)action);
            [(NoshiChatExtrasController *)weak.target rebuild];
        });
    }];
}

/* the emoji a double tap sends; the chat falls back to its first reaction when it does not offer the one chosen */
- (NoshiSettingsRow *)quickReactionRow {
    NoshiWeakReference *weak = _weak;
    BOOL enabled = NoshiChatQuickReactionEnabled();
    NoshiSettingsRow *row = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.quickreaction", nil) value:enabled ? NoshiChatQuickReactionDisplay() : NSLocalizedString(@"chatset.quickreaction.off", nil) tap:^{
        NoshiChatExtrasController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[NoshiQuickReactionController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    row.valueIsEmoji = enabled;
    row.valueEmojiDocument = enabled ? noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String) : 0;
    return row;
}

- (void)stickerScaleMoved:(float)value {
    NSInteger percent = (NSInteger)(value + 0.5f);
    if (percent == NoshiChatStickerScale()) return;
    NoshiChatSetStickerScale(percent);
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
}

/* how messages look and answer a tap */
- (NoshiSettingsSection *)messagesSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiFlagRow(@"chatset.mentioncomma", @"chatset.mentioncomma.info", NoshiChatFlagCommaAfterMention)];
    [rows addObject:NoshiFlagRow(@"chatset.editedicon", nil, NoshiChatFlagEditedIcon)];
    [rows addObject:NoshiFlagRow(@"chatset.notail", nil, NoshiChatFlagRemoveTail)];
    [rows addObject:NoshiFlagRow(@"chatset.pollresults", @"chatset.pollresults.info", NoshiChatFlagPollResultsFirst)];
    [rows addObject:NoshiFlagRow(@"chatset.forwarddate", nil, NoshiChatFlagForwardDate)];
    [rows addObject:NoshiFlagRow(@"chatset.forwardauthor", @"chatset.forwardauthor.info", NoshiChatFlagForwardAuthor)];
    [rows addObject:NoshiFlagRow(@"chatset.hideshare", nil, NoshiChatFlagHideShare)];
    [rows addObject:NoshiFlagRow(@"chatset.hidesendas", @"chatset.hidesendas.info", NoshiChatFlagHideSendAs)];
    [rows addObject:NoshiFlagRow(@"chatset.noreactions.private", nil, NoshiChatFlagHideReactionsPrivate)];
    [rows addObject:NoshiFlagRow(@"chatset.noreactions.groups", nil, NoshiChatFlagHideReactionsGroups)];
    [rows addObject:NoshiFlagRow(@"chatset.noreactions.channels", nil, NoshiChatFlagHideReactionsChannels)];
    [rows addObject:[self doubleTapRowOutgoing:NO]];
    [rows addObject:[self doubleTapRowOutgoing:YES]];
    [rows addObject:[self quickReactionRow]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.messages.header", nil) footer:NSLocalizedString(@"chatset.doubletap.info", nil) rows:rows];
}

/* the entries the menu of a message may add */
- (NoshiSettingsSection *)menuSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiFlagRow(@"chatset.menu.save", nil, NoshiChatFlagMenuSave)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.repeat", nil, NoshiChatFlagMenuRepeat)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.details", nil, NoshiChatFlagMenuDetails)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.bookmark", nil, NoshiChatFlagMenuBookmark)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.copyphoto", nil, NoshiChatFlagMenuCopyPhoto)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.noquote", nil, NoshiChatFlagMenuNoQuote)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.history", nil, NoshiChatFlagMenuHistory)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.report", nil, NoshiChatFlagMenuReport)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.remind", nil, NoshiChatFlagMenuRemind)];
    [rows addObject:NoshiFlagRow(@"chatset.menu.replyprivate", nil, NoshiChatFlagMenuReplyPrivate)];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.menu.header", nil) footer:NSLocalizedString(@"chatset.menu.header.info", nil) rows:rows];
}

/* the questions asked before something that cannot be taken back, and what happens to a link */
- (NoshiSettingsSection *)confirmSection {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiFlagRow(@"chatset.askcall", nil, NoshiChatFlagAskCall)];
    [rows addObject:NoshiFlagRow(@"chatset.askrepeat", nil, NoshiChatFlagAskRepeat)];
    [rows addObject:NoshiFlagRow(@"chatset.askrecording", nil, NoshiChatFlagAskRecording)];
    [rows addObject:NoshiFlagRow(@"chatset.askbotcommand", nil, NoshiChatFlagAskBotCommand)];
    static NSString *const keys[] = {@"chatset.linkask.never", @"chatset.linkask.hidden", @"chatset.linkask.always"};
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.linkask", nil) value:NSLocalizedString(keys[NoshiChatLinkConfirm()], nil) tap:^{
        NoshiChatExtrasController *me = weak.target;
        if (!me) return;
        NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(keys[0], nil), NSLocalizedString(keys[1], nil), NSLocalizedString(keys[2], nil), nil];
        NoshiSettingsChoose(me, NSLocalizedString(@"chatset.linkask", nil), options, ^(NSUInteger index) {
            NoshiChatSetLinkConfirm((NoshiLinkConfirm)index);
            [(NoshiChatExtrasController *)weak.target rebuild];
        });
    }]];
    [rows addObject:NoshiFlagRow(@"chatset.nolinkpreview", @"chatset.nolinkpreview.info", NoshiChatFlagNoLinkPreview)];
    [rows addObject:NoshiFlagRow(@"chatset.deleteforme", @"chatset.deleteforme.info", NoshiChatFlagDeleteForMe)];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.confirm.header", nil) footer:nil rows:rows];
}

@end
