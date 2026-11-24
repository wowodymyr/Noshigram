#import "noshi_settings_extras.h"
#import "noshi_alert.h"
#import "noshi_browser_settings.h"
#import "noshi_chat_settings.h"
#import "noshi_language.h"
#import "noshi_settings_reset.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_time_zone_controller.h"
#import "noshi_translate_config.h"
#import "noshi_translate_languages_controller.h"
#import "noshi_translator_controller.h"

static void NoshiExtrasRebuild(NoshiWeakReference *weak) {
    id page = weak.target;
    if ([page respondsToSelector:@selector(rebuild)]) [page performSelector:@selector(rebuild)];
}

static void NoshiExtrasPush(NoshiWeakReference *weak, UIViewController *next) {
    [[(UIViewController *)weak.target navigationController] pushViewController:next animated:YES];
}

/* every screen reads these settings when it is built, so the main controller builds them again on this notification, from the row that was touched */
static void NoshiExtrasApplyLook(NoshiWeakReference *weak) {
    NoshiSettingsPageController *page = weak.target;
    if (!page) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:page.selectPoint] forKey:NoshiThemeOriginKey]];
}

/* a switch that sets a flag of the chat settings and tells what listens (the chat list, the demo dialog) */
static NoshiSettingsRow *NoshiExtrasFlagRow(NSString *titleKey, NSString *infoKey, NoshiChatFlag flag) {
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil
                                               on:NoshiChatFlagGet(flag) toggle:^(BOOL on) {
        NoshiChatFlagSet(flag, on);
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    }];
}

/* a switch whose change the screens only show once they are built again */
static NoshiSettingsRow *NoshiExtrasLookFlagRow(NoshiWeakReference *weak, NSString *titleKey, NoshiChatFlag flag, BOOL inverted) {
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:nil on:NoshiChatFlagGet(flag) != inverted toggle:^(BOOL on) {
        NoshiChatFlagSet(flag, on != inverted);
        NoshiExtrasApplyLook(weak);
    }];
}

#pragma mark language

static NSString *NoshiTranslateTargetSummary(void) {
    NSString *choice = NoshiTranslateTargetChoice();
    return choice.length ? NoshiLanguageName(choice) : NSLocalizedString(@"tr.target.app", nil);
}

static NSString *NoshiTranslateSkippedSummary(void) {
    NSUInteger count = NoshiTranslateSkippedLanguages().count;
    return count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil;
}

NoshiSettingsSection *NoshiTranslateSettingsSection(NoshiWeakReference *weak) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"general.translate.button", nil) subtitle:nil on:NoshiTranslateButtonEnabled()
                                                    toggle:^(BOOL on) { NoshiTranslateSetButtonEnabled(on); }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.provider", nil) value:NoshiTranslateProviderName(NoshiTranslateProviderChoice()) tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NSArray *ids = NoshiTranslateProviderList();
        NSMutableArray *titles = [NSMutableArray array];
        for (NSNumber *provider in ids) [titles addObject:NoshiTranslateProviderName(provider.intValue)];
        NoshiSettingsChoose(page, NSLocalizedString(@"tr.provider", nil), titles, ^(NSUInteger index) {
            NoshiTranslateSetProviderChoice([[ids objectAtIndex:index] intValue]);
            NoshiExtrasRebuild(weak);
        });
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.target", nil) value:NoshiTranslateTargetSummary() tap:^{
        NoshiExtrasPush(weak, [[[NoshiTranslateLanguagesController alloc] initWithMode:NoshiTranslateLanguagesTarget] autorelease]);
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.skip", nil) value:NoshiTranslateSkippedSummary() tap:^{
        NoshiExtrasPush(weak, [[[NoshiTranslateLanguagesController alloc] initWithMode:NoshiTranslateLanguagesSkipped] autorelease]);
    }]];
    [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolTranslate tone:NoshiSettingsTonePurple title:NSLocalizedString(@"tr.title", nil) subtitle:nil value:nil tap:^{
        NoshiExtrasPush(weak, [[[NoshiTranslatorSettingsController alloc] init] autorelease]);
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"general.translate.header", nil) footer:NSLocalizedString(@"general.translate.info", nil) rows:rows];
}

NoshiSettingsSection *NoshiFormatSettingsSection(NoshiWeakReference *weak) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiExtrasFlagRow(@"general.exactnumbers", @"general.exactnumbers.value", NoshiChatFlagExactNumbers)];
    [rows addObject:NoshiExtrasFlagRow(@"general.seconds", @"general.seconds.value", NoshiChatFlagSeconds)];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"time.zone.title", nil) value:NoshiTimeZoneChoiceText() tap:^{
        NoshiExtrasPush(weak, [[[NoshiTimeZoneController alloc] init] autorelease]);
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"language.format.header", nil) footer:nil rows:rows];
}

#pragma mark chat settings

static void NoshiChooseListTitle(NoshiWeakReference *weak) {
    UIViewController *page = weak.target;
    if (!page) return;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"look.title.default", nil), NSLocalizedString(@"look.title.username", nil),
                        NSLocalizedString(@"look.title.name", nil), NSLocalizedString(@"look.title.custom", nil), nil];
    NoshiSettingsChoose(page, NSLocalizedString(@"look.title", nil), options, ^(NSUInteger index) {
        if (!weak.target) return;
        if (index == NoshiChatListTitleCustom) {
            NoshiPromptText(NSLocalizedString(@"look.title.custom", nil), nil, NoshiChatListCustomTitle(), NSLocalizedString(@"look.title.hint", nil), ^(NSString *text) {
                if (!weak.target) return;
                NoshiChatListSetCustomTitle(text);
                NoshiChatListTitleStore(NoshiChatListTitleCustom);
                NoshiExtrasApplyLook(weak);
            });
            return;
        }
        NoshiChatListTitleStore((NoshiChatListTitle)index);
        NoshiExtrasApplyLook(weak);
    });
}

NSArray *NoshiChatListExtraRows(NoshiWeakReference *weak) {
    static NSString *const titleKeys[] = {@"look.title.default", @"look.title.username", @"look.title.name", @"look.title.custom"};
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiExtrasLookFlagRow(weak, @"look.stories", NoshiChatFlagHideStories, YES)];
    [rows addObject:NoshiExtrasLookFlagRow(weak, @"look.hidesearch", NoshiChatFlagHideSearchBar, NO)];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"look.title", nil) value:NSLocalizedString(titleKeys[NoshiChatListTitleStored()], nil) tap:^{
        NoshiChooseListTitle(weak);
    }]];
    [rows addObject:NoshiExtrasLookFlagRow(weak, @"look.senderavatars", NoshiChatFlagSenderAvatars, NO)];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"general.hidearchive", nil) subtitle:nil on:NoshiArchiveHidden() toggle:^(BOOL on) {
        NoshiArchiveSetHidden(on);
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    }]];
    [rows addObject:NoshiExtrasFlagRow(@"general.nounarchive", @"general.nounarchive.info", NoshiChatFlagNoUnarchiveSwipe)];
    return rows;
}

NSArray *NoshiPlaybackExtraRows(NoshiWeakReference *weak) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.seek", nil)
                                               value:[NSString stringWithFormat:NSLocalizedString(@"chatset.seek.value", nil), (int)NoshiChatSeekSeconds()] tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NSArray *options = [NSArray arrayWithObjects:@"5", @"10", @"15", @"30", nil];
        NoshiSettingsChoose(page, NSLocalizedString(@"chatset.seek", nil), options, ^(NSUInteger index) {
            NoshiChatSetSeekSeconds([[options objectAtIndex:index] integerValue]);
            NoshiExtrasRebuild(weak);
        });
    }]];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.pausevoice", nil, NoshiChatFlagPauseVoiceOnMinimize)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.pauseround", nil, NoshiChatFlagPauseRoundOnMinimize)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.noautonext", nil, NoshiChatFlagNoAutoNextVoice)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.unmutevolume", @"chatset.unmutevolume.info", NoshiChatFlagUnmuteWithVolume)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.alwayshd", @"chatset.alwayshd.info", NoshiChatFlagAlwaysHD)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.hidecameratile", nil, NoshiChatFlagHideCameraTile)];
    return rows;
}

/* what a double tap does is a choice of ten, kept apart for the messages of others and our own */
static NoshiSettingsRow *NoshiDoubleTapRow(NoshiWeakReference *weak, BOOL outgoing) {
    static NSString *const keys[NoshiDoubleTapCount] = {
        @"chatset.dt.none", @"chatset.dt.reaction", @"chatset.dt.picker", @"chatset.dt.translate", @"chatset.dt.reply",
        @"chatset.dt.forward", @"chatset.dt.save", @"chatset.dt.repeat", @"chatset.dt.edit", @"chatset.dt.delete"};
    NSString *title = NSLocalizedString(outgoing ? @"chatset.doubletap.out" : @"chatset.doubletap.in", nil);
    return [NoshiSettingsRow rowWithTitle:title value:NSLocalizedString(keys[NoshiChatDoubleTap(outgoing)], nil) tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NSMutableArray *options = [NSMutableArray array];
        /* editing is only for our own messages */
        for (int action = 0; action < NoshiDoubleTapCount; ++action) {
            if (action == NoshiDoubleTapEdit && !outgoing) continue;
            [options addObject:NSLocalizedString(keys[action], nil)];
        }
        NoshiSettingsChoose(page, title, options, ^(NSUInteger index) {
            int action = (int)index;
            if (!outgoing && action >= NoshiDoubleTapEdit) ++action;
            NoshiChatSetDoubleTap(outgoing, (NoshiDoubleTapAction)action);
            NoshiExtrasRebuild(weak);
        });
    }];
}

/* how messages look and answer a tap */
NoshiSettingsSection *NoshiMessagesSettingsSection(NoshiWeakReference *weak) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.replybackground", nil, NoshiChatFlagReplyBackground)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.mentioncomma", @"chatset.mentioncomma.info", NoshiChatFlagCommaAfterMention)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.editedicon", nil, NoshiChatFlagEditedIcon)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.notail", nil, NoshiChatFlagRemoveTail)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.pollresults", @"chatset.pollresults.info", NoshiChatFlagPollResultsFirst)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.forwarddate", nil, NoshiChatFlagForwardDate)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.forwardauthor", @"chatset.forwardauthor.info", NoshiChatFlagForwardAuthor)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.hideshare", nil, NoshiChatFlagHideShare)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.hidesendas", @"chatset.hidesendas.info", NoshiChatFlagHideSendAs)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.noreactions.private", nil, NoshiChatFlagHideReactionsPrivate)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.noreactions.groups", nil, NoshiChatFlagHideReactionsGroups)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.noreactions.channels", nil, NoshiChatFlagHideReactionsChannels)];
    [rows addObject:NoshiExtrasFlagRow(@"general.zalgo", @"general.zalgo.info", NoshiChatFlagFilterZalgo)];
    [rows addObject:NoshiDoubleTapRow(weak, NO)];
    [rows addObject:NoshiDoubleTapRow(weak, YES)];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.messages.header", nil) footer:NSLocalizedString(@"chatset.doubletap.info", nil) rows:rows];
}

NoshiSettingsSection *NoshiPremiumElementsSection(void) {
    NSArray *rows = [NSArray arrayWithObjects:
        NoshiExtrasFlagRow(@"chatset.premium.status", nil, NoshiChatFlagShowMessageEmojiStatus),
        NoshiExtrasFlagRow(@"chatset.premium.replyemoji", nil, NoshiChatFlagShowReplyCustomEmoji),
        NoshiExtrasFlagRow(@"chatset.replycolors", @"chatset.replycolors.info", NoshiChatFlagReplyColors), nil];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.premium.header", nil) footer:nil rows:rows];
}

/* the entries the menu of a message may add */
NoshiSettingsSection *NoshiMessageMenuSection(void) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.save", nil, NoshiChatFlagMenuSave)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.repeat", nil, NoshiChatFlagMenuRepeat)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.details", nil, NoshiChatFlagMenuDetails)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.bookmark", nil, NoshiChatFlagMenuBookmark)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.copyphoto", nil, NoshiChatFlagMenuCopyPhoto)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.noquote", nil, NoshiChatFlagMenuNoQuote)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.history", nil, NoshiChatFlagMenuHistory)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.report", nil, NoshiChatFlagMenuReport)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.remind", nil, NoshiChatFlagMenuRemind)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.menu.replyprivate", nil, NoshiChatFlagMenuReplyPrivate)];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.menu.header", nil) footer:NSLocalizedString(@"chatset.menu.header.info", nil) rows:rows];
}

NoshiSettingsSection *NoshiResetSettingsSection(NoshiWeakReference *weak) {
    NoshiSettingsRow *reset = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolRotate title:NSLocalizedString(@"more.reset", nil) destructive:YES tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NoshiConfirmAction(page, NSLocalizedString(@"more.reset.info", nil), NSLocalizedString(@"more.reset", nil), ^{
            NoshiResetSettings();
            NoshiExtrasApplyLook(weak);
        });
    }];
    return [NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"more.reset.footer", nil) rows:[NSArray arrayWithObject:reset]];
}

#pragma mark stickers

NSArray *NoshiStickerLookRows(NoshiWeakReference *weak) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.stickersize", nil) format:@"%.0f%%" value:(float)NoshiChatStickerScale()
                                                   minimum:NOSHI_STICKER_SCALE_MIN maximum:NOSHI_STICKER_SCALE_MAX change:^(float value) {
        NSInteger percent = (NSInteger)(value + 0.5f);
        if (percent == NoshiChatStickerScale()) return;
        NoshiChatSetStickerScale(percent);
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    }]];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.hidestickertime", nil, NoshiChatFlagHideStickerTime)];
    static NSString *const shapes[] = {@"chatset.shape.none", @"chatset.shape.rounded", @"chatset.shape.bubble"};
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.stickershape", nil) value:NSLocalizedString(shapes[NoshiChatStickerShape()], nil) tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(shapes[0], nil), NSLocalizedString(shapes[1], nil), NSLocalizedString(shapes[2], nil), nil];
        NoshiSettingsChoose(page, NSLocalizedString(@"chatset.stickershape", nil), options, ^(NSUInteger index) {
            NoshiChatSetStickerShape((NoshiStickerShape)index);
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
            NoshiExtrasRebuild(weak);
        });
    }]];
    return rows;
}

#pragma mark folders

NoshiSettingsSection *NoshiFolderTabsSection(NoshiWeakReference *weak) {
    NSArray *styles = [NSArray arrayWithObjects:NSLocalizedString(@"look.folders.style.names", nil), NSLocalizedString(@"look.folders.style.icons", nil),
                       NSLocalizedString(@"look.folders.style.both", nil), nil];
    /* the bar of folders on the screen changes in place, so the page only has to show the choice */
    NoshiSettingsRow *style = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"look.folders.style", nil)
                                                           value:[styles objectAtIndex:(NSUInteger)NoshiFolderTabStyleStored()] tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NoshiSettingsChoose(page, NSLocalizedString(@"look.folders.style", nil), styles, ^(NSUInteger index) {
            NoshiFolderTabStyleStore((NoshiFolderTabStyle)index);
            NoshiExtrasRebuild(weak);
        });
    }];
    NoshiSettingsRow *hide = [NoshiSettingsRow switchRowWithTitle:[NSString stringWithFormat:NSLocalizedString(@"look.hidealltab", nil), NSLocalizedString(@"folders.all", nil)]
                                                             subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagHideAllChatsTab) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagHideAllChatsTab, on);
        NoshiExtrasApplyLook(weak);
    }];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.folders.header", nil) footer:NSLocalizedString(@"look.folders.info", nil)
                                                rows:[NSArray arrayWithObjects:style, hide, nil]];
}

#pragma mark privacy

NoshiSettingsSection *NoshiProfileDisplaySection(void) {
    NSArray *rows = [NSArray arrayWithObjects:NoshiExtrasFlagRow(@"general.hidephone", nil, NoshiChatFlagHidePhone),
                     NoshiExtrasFlagRow(@"general.showids", nil, NoshiChatFlagShowIds), nil];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"general.profile.header", nil) footer:NSLocalizedString(@"general.showids.info", nil) rows:rows];
}

/* the questions asked before something that cannot be taken back, and what happens to a link */
NoshiSettingsSection *NoshiConfirmSettingsSection(NoshiWeakReference *weak) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.askcall", nil, NoshiChatFlagAskCall)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.askrepeat", nil, NoshiChatFlagAskRepeat)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.askrecording", nil, NoshiChatFlagAskRecording)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.askbotcommand", nil, NoshiChatFlagAskBotCommand)];
    static NSString *const keys[] = {@"chatset.linkask.never", @"chatset.linkask.hidden", @"chatset.linkask.always"};
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.linkask", nil) value:NSLocalizedString(keys[NoshiChatLinkConfirm()], nil) tap:^{
        UIViewController *page = weak.target;
        if (!page) return;
        NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(keys[0], nil), NSLocalizedString(keys[1], nil), NSLocalizedString(keys[2], nil), nil];
        NoshiSettingsChoose(page, NSLocalizedString(@"chatset.linkask", nil), options, ^(NSUInteger index) {
            NoshiChatSetLinkConfirm((NoshiLinkConfirm)index);
            NoshiExtrasRebuild(weak);
        });
    }]];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.nolinkpreview", @"chatset.nolinkpreview.info", NoshiChatFlagNoLinkPreview)];
    [rows addObject:NoshiExtrasFlagRow(@"chatset.deleteforme", @"chatset.deleteforme.info", NoshiChatFlagDeleteForMe)];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.confirm.header", nil) footer:nil rows:rows];
}
