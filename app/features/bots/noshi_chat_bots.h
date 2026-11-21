#import <UIKit/UIKit.h>

#import "noshi_input_bar.h"
#import "noshi_weak_reference.h"
#import "noshi_link_router.h"
#import "noshi_message_cell.h"
#import "noshi_session_bots.h"
#import "noshi_suggestion_panel.h"

@class NoshiChatBots;

/* what the coordinator asks of the chat screen it serves */
@protocol NoshiChatBotsHost <NSObject>
- (NoshiInputBar *)botsInputBar;
/* the view the panels and cards are added to */
- (UIView *)botsContainerView;
/* sends text as the person's own message in this chat */
- (void)botsSendText:(NSString *)text replyTo:(int32_t)replyTo;
- (long long)botsRandomId;
- (int32_t)botsInlineReplyId;
- (void)botsInlineDidSendReply:(int32_t)replyId;
- (BOOL)botsCanSendInline;
/* the geometry of the bar or the panels changed */
- (void)botsRelayout;
/* the view that stands in for the system keyboard, nil to give the system keyboard back */
- (void)botsSetInputView:(UIView *)view;
/* the room a replacement keyboard may take */
- (CGFloat)botsKeyboardMaxHeight;
/* the user with this id, as the history of the chat named them; nil when it did not */
- (NoshiPerson *)botsPersonForUserId:(long long)userId;
/* the chat shares the person's position, which arrives as a message of its own */
- (void)botsRequestLocation;
/* puts text in the field and opens the keyboard */
- (void)botsSetDraft:(NSString *)text;
/* the people of this chat the history has named, for the names offered after an @ */
- (NSArray *)botsMentionCandidates;
@end

/* everything a chat does for bots, so the screen only forwards what happens in it */
@interface NoshiChatBots : NSObject {
    NoshiSession *_session;
    NoshiDialog *_dialog;
    NoshiLinkRouter *_router;
    id<NoshiChatBotsHost> _host;
    NoshiWeakReference *_weak;
    NoshiMediaCache *_media;
}

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog router:(NoshiLinkRouter *)router media:(NoshiMediaCache *)media
                 host:(id<NoshiChatBotsHost>)host;

@property (nonatomic, assign) id<NoshiChatBotsHost> host;
/* the parameter the first press of Start sends, from a link; nil for none */
@property (nonatomic, copy) NSString *startParam;
/* the panel over the bar while commands or answers are offered, nil while none is */
@property (nonatomic, readonly) NoshiSuggestionPanel *panel;
/* the card with the bot's description in an empty chat, nil when there is none to show */
@property (nonatomic, readonly) UIView *card;

/* loads what a bot says about itself; a chat with anyone else does nothing */
- (void)start;
/* the messages of the chat in order, oldest first, after each change; loaded says the first page has arrived */
- (void)messagesChanged:(NSArray *)messages loaded:(BOOL)loaded;
/* the text in the field changed */
- (void)inputTextChanged;
/* the message a text typed now answers: the one a bot asked for an answer to, zero otherwise */
- (int32_t)replyTargetForText;
/* the person sent something themselves */
- (void)didSendText;

/* the emoji panel is about to take the place of the keyboard or give it back: a bot's keyboard that was open steps aside */
- (void)emojiPanelWillChange;

/* the bar's pill, keyboard button and wide button */
- (void)menuTapped;
- (void)keyboardButtonTapped;
- (void)actionTapped;

/* a button under message was pressed; the cell shows the spinner while the answer is awaited */
- (void)pressButton:(NoshiMarkupButton *)button ofMessage:(NoshiMessage *)message cell:(NoshiMessageCell *)cell;
/* a link in a message: a command, a name, an address */
- (BOOL)openLink:(NSString *)url;

/* puts the card in the middle of the room the chat leaves free */
- (void)layoutCardInRect:(CGRect)rect;
/* the height the panel wants for the width, and its place is up to the screen */
- (CGFloat)panelHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;
/* stops everything that is still waiting for an answer */
- (void)teardown;

@end
