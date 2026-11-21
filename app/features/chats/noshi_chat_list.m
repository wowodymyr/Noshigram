#import "noshi_chat_list.h"

#import "noshi_chat_settings.h"

NSString *const NoshiUnreadTotalDidChangeNotification = @"NoshiUnreadTotalDidChange";
static NSArray *sMainDialogsSnapshot;
static NSInteger sUnreadTotal;

NSArray *NoshiMainDialogsSnapshot(void) { return sMainDialogsSnapshot; }

void NoshiSetMainDialogsSnapshot(NSArray *dialogs) {
    [sMainDialogsSnapshot release];
    sMainDialogsSnapshot = [dialogs retain];
}

NSInteger NoshiUnreadTotal(void) { return sUnreadTotal; }

void NoshiSetUnreadTotal(NSInteger total) {
    if (total == sUnreadTotal) return;
    sUnreadTotal = total;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiUnreadTotalDidChangeNotification object:nil];
}

NoshiDialogAction NoshiDialogSwipeAction(NoshiDialog *dialog, NSInteger folderId) {
    if (folderId > 0) return NoshiChatFlagGet(NoshiChatFlagNoUnarchiveSwipe) ? NoshiDialogActionNone : NoshiDialogActionUnarchive;
    switch (NoshiChatSwipeStored()) {
    case NoshiChatSwipePin: return dialog.pinned ? NoshiDialogActionUnpinChat : NoshiDialogActionPinChat;
    case NoshiChatSwipeRead: return dialog.unread ? NoshiDialogActionMarkRead : NoshiDialogActionMarkUnread;
    case NoshiChatSwipeMute: return dialog.muted ? NoshiDialogActionUnmute : NoshiDialogActionMute;
    case NoshiChatSwipeDelete: return NoshiDialogActionDeleteChat;
    case NoshiChatSwipeFolders: return NoshiDialogActionNone;
    case NoshiChatSwipeArchive: break;
    }
    return dialog.saved ? NoshiDialogActionNone : NoshiDialogActionArchive;
}

NSString *NoshiDialogActionText(NoshiDialogAction action) {
    switch (action) {
    case NoshiDialogActionArchive: return NSLocalizedString(@"chats.archive.action", nil);
    case NoshiDialogActionUnarchive: return NSLocalizedString(@"chats.unarchive.action", nil);
    case NoshiDialogActionHide: return NSLocalizedString(@"chats.hide.action", nil);
    case NoshiDialogActionPin: return NSLocalizedString(@"chats.pin.action", nil);
    case NoshiDialogActionPinChat: return NSLocalizedString(@"chats.swipe.pin", nil);
    case NoshiDialogActionUnpinChat: return NSLocalizedString(@"chats.swipe.unpin", nil);
    case NoshiDialogActionMarkRead: return NSLocalizedString(@"chats.swipe.read", nil);
    case NoshiDialogActionMarkUnread: return NSLocalizedString(@"chats.swipe.unread", nil);
    case NoshiDialogActionMute: return NSLocalizedString(@"chats.swipe.mute", nil);
    case NoshiDialogActionUnmute: return NSLocalizedString(@"chats.swipe.unmute", nil);
    case NoshiDialogActionDeleteChat: return NSLocalizedString(@"chats.swipe.delete", nil);
    case NoshiDialogActionNone: break;
    }
    return @"";
}
