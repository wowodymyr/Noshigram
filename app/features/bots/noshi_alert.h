#import <Foundation/Foundation.h>

/* the index of the button pressed, counted in the order the titles were given, and the text of the field when the alert has one */
typedef void (^NoshiAlertHandler)(NSInteger index, NSString *text);

/* an alert with any number of buttons that reports the choice to a block */
void NoshiShowAlert(NSString *title, NSString *message, NSArray *buttons, NSInteger cancelIndex, BOOL secure, NoshiAlertHandler handler);

/* a message with one button */
void NoshiShowNotice(NSString *title, NSString *message);

/* a question with a confirming button and a cancel one; the handler runs only for the confirming one */
void NoshiConfirm(NSString *title, NSString *message, NSString *confirmTitle, void (^handler)(void));

/* a list of choices on a sheet, with a cancel at the end; the handler gets the index of the choice, not of the
   cancel */
void NoshiChoose(NSString *title, NSArray *choices, NSInteger destructiveIndex, void (^handler)(NSInteger index));
/* the same, opened from a view: on an ipad the sheet is a popover that points at it, where NoshiChoose puts it in the middle of the screen, far from the button that asked for it; on a
   phone it is the sheet from the bottom as before */
void NoshiChooseFromView(UIView *source, NSString *title, NSArray *choices, NSInteger destructiveIndex, void (^handler)(NSInteger index));

/* the choices on the system sheet whatever the style: the system puts it in a window of its own above the keyboard, which the sheet of the application is not, so a choice asked
   while the emoji and sticker panel stands in the place of the keyboard is seen here and hidden under the panel there */
void NoshiChooseWithSystemSheet(UIView *source, NSString *title, NSArray *choices, NSInteger destructiveIndex, void (^handler)(NSInteger index));

/* NoshiPromptText, and dismissed runs once the alert is off the screen whichever button closed it, for a caller that gives the keyboard back to a field the alert took it from */
void NoshiPromptTextThen(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text), void (^dismissed)(void));

/* the same, and cancelled runs when the question is turned down instead (Cancel, or the application going to the background) */
void NoshiPromptTextOrCancel(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text), void (^cancelled)(void));

/* a question with one text field filled with initial; the handler runs with the text only when OK is pressed, and with an empty string for an emptied field */
void NoshiPromptText(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text));
