#import "noshi_quick_reaction_controller.h"

#import <QuartzCore/QuartzCore.h>
#import "noshi_chat_settings.h"
#import "noshi_chat_preview_view.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_emoji_label.h"
#import "noshi_gift_screen.h"
#import "noshi_person.h"
#import "noshi_reaction_picker.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#include "noshi_reactions.h"

void NoshiLoadQuickReactionPicture(NoshiSession *session, NoshiMediaCache *media, void (^picture)(void)) {
    long long document = noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String);
    if (document && session && media)
        [NoshiCustomEmojiLoader loadDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] session:session media:media documents:nil picture:picture];
}

@interface NoshiQuickReactionController () {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NoshiReactionPicker *_picker;
    NSArray *_choices;
    NSString *_error;
    BOOL _loaded;
    BOOL _premiumKnown;
    BOOL _premium;
}
@end

@implementation NoshiQuickReactionController
- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.quickreaction", nil);
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_picker dismissAnimated:NO];
    [_picker release];
    [_weak release]; [_media release]; [_session release]; [_choices release]; [_error release];
    [super dealloc];
}
- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiQuickReactionController alloc] initWithSession:_session] autorelease];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    _media = [[NoshiMediaCache alloc] initWithSession:_session directory:[[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"media"]];
    [self rebuild];
    [self load];
}
- (void)load {
    _loaded = NO;
    _premiumKnown = NO;
    [_error release]; _error = nil;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiQuickReactionController *screen = weak.target;
        if (!screen) return;
        NoshiPerson *person = items.count ? [items objectAtIndex:0] : nil;
        if (!person) {
            screen->_loaded = YES;
            screen->_error = [(errorName ? errorName : @"INTERNAL") copy];
            [screen rebuild];
            return;
        }
        screen->_premiumKnown = YES;
        screen->_premium = NoshiPremiumEffective(person.premium);
        long long account = [NoshiSession accountIdInDirectory:screen->_session.directory];
        NoshiDialog *saved = account > 0 ? [NoshiDialog savedMessagesOfUserId:account] : nil;
        if (!saved) { screen->_loaded = YES; screen->_error = [@"INTERNAL" copy]; [screen rebuild]; return; }
        [screen->_session loadAvailableReactionsForDialog:saved premium:screen->_premium completion:^(NSArray *choices, NSString *failure) {
            NoshiQuickReactionController *page = weak.target;
            if (!page) return;
            page->_loaded = YES;
            [page->_choices release]; page->_choices = [choices copy];
            [page->_error release]; page->_error = [failure copy];
            [page rebuild];
        }];
    }];
    long long document = noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String);
    if (document) [NoshiCustomEmojiLoader loadDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] session:_session media:_media documents:nil picture:^{
        [(NoshiQuickReactionController *)weak.target rebuild];
    }];
}
- (void)closePicker {
    [_picker dismissAnimated:self.view.window != nil];
    [_picker release];
    _picker = nil;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self closePicker];
}
- (void)openPicker {
    if (_picker || !_choices || !_premiumKnown) return;
    _picker = [[NoshiReactionPicker alloc] initWithFrame:self.view.bounds];
    _picker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_picker attachSession:_session media:_media premium:_premium];
    NSMutableArray *marked = [NSMutableArray array];
    for (NoshiReaction *choice in _choices) {
        noshi_reaction row = choice.row;
        row.chosen = (row.kind == NOSHI_REACTION_EMOJI && [choice.emoji isEqualToString:NoshiChatQuickReaction()]) ||
            (row.kind == NOSHI_REACTION_CUSTOM && row.document_id == noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String));
        [marked addObject:[NoshiReaction reactionWithRow:&row]];
    }
    [_picker setReactions:marked];
    NoshiWeakReference *weak = _weak;
    _picker.cancelHandler = ^{ [(NoshiQuickReactionController *)weak.target closePicker]; };
    _picker.pickHandler = ^(NoshiReaction *reaction) {
        NoshiQuickReactionController *page = weak.target;
        if (!page) return;
        if (reaction.row.kind == NOSHI_REACTION_CUSTOM && !page->_premium) { NoshiGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil)); return; }
        if (reaction.row.kind == NOSHI_REACTION_EMOJI && reaction.emoji.length) NoshiChatSetQuickReaction(reaction.emoji);
        else if (reaction.row.kind == NOSHI_REACTION_CUSTOM && reaction.row.document_id > 0)
            NoshiChatSetQuickCustomReaction(reaction.row.document_id, reaction.displayText);
        else return;
        [page closePicker];
        [page rebuild];
    };
    _picker.customPickHandler = ^(NoshiCustomEmojiDocument *emoji) {
        NoshiQuickReactionController *page = weak.target;
        if (!page || emoji.documentId <= 0) return;
        if (!page->_premium) { NoshiGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil)); return; }
        NoshiChatSetQuickCustomReaction(emoji.documentId, emoji.alt);
        [page closePicker];
        [page rebuild];
    };
    [self.view addSubview:_picker];
}
- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiChatPreviewView *preview = [[[NoshiChatPreviewView alloc] initWithTalk:NoshiChatPreviewTalkQuickReaction] autorelease];
    [preview setQuickReaction:NoshiChatQuickReaction() display:NoshiChatQuickReactionDisplay()];
    preview.heightHandler = ^{ [(NoshiQuickReactionController *)weak.target updateRowHeights]; };
    NoshiSettingsRow *previewRow = [NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }];
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil
        footer:NSLocalizedString(@"chatset.quickreaction.info", nil) rows:[NSArray arrayWithObject:previewRow]]];
    BOOL enabled = NoshiChatQuickReactionEnabled();
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
        [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.quickreaction.enable", nil) subtitle:nil on:enabled toggle:^(BOOL on) {
            NoshiChatSetQuickReactionEnabled(on);
            [(NoshiQuickReactionController *)weak.target rebuild];
        }]]]];
    NSMutableArray *rows = [NSMutableArray array];
    if (enabled && _premiumKnown && _choices) {
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.quickreaction", nil) value:nil tap:^{
            [(NoshiQuickReactionController *)weak.target openPicker];
        }]];
    }
    if (_error) [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"list.retry", nil) value:nil tap:^{
        [(NoshiQuickReactionController *)weak.target load];
    }]];
    NSString *footer = !_loaded ? NSLocalizedString(@"profile.loading", nil) : (_error ? NoshiGiftErrorText(_error) : (rows.count ? nil : NSLocalizedString(@"chats.nothing", nil)));
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}
@end
