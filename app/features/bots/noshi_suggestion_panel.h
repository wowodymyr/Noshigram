#import <UIKit/UIKit.h>

#import "noshi_bot.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"

/* one row of the panel above the field: a command a bot offers or a result of an inline query */
@interface NoshiSuggestion : NSObject {
    NSString *_title;
    NSString *_subtitle;
    NoshiMedia *_media;
    NoshiWebFile *_webFile;
    id _payload;
}
- (id)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle media:(NoshiMedia *)media webFile:(NoshiWebFile *)webFile payload:(id)payload;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *subtitle;
/* the picture the server holds, or the one the bot hosts; both nil for a row without a picture */
@property (nonatomic, readonly, retain) NoshiMedia *media;
@property (nonatomic, readonly, retain) NoshiWebFile *webFile;
@property (nonatomic, readonly, retain) id payload;
@end

/* the list over the chat that follows what is typed: the commands of a bot after a slash, the answers of a bot
   after its name */
@interface NoshiSuggestionPanel : UIView <UITableViewDataSource, UITableViewDelegate> {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    UITableView *_table;
    UIActivityIndicatorView *_spinner;
    UILabel *_empty;
    NSMutableArray *_items;
    BOOL _gallery;
    NSString *_headerTitle;
    void (^_pickHandler)(NoshiSuggestion *suggestion);
    void (^_headerHandler)(void);
    void (^_moreHandler)(void);
}

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;

@property (nonatomic, copy) void (^pickHandler)(NoshiSuggestion *suggestion);
/* asked for when the list is scrolled to its end; the owner appends the next page */
@property (nonatomic, copy) void (^moreHandler)(void);

/* replaces the rows */
- (void)setSuggestions:(NSArray *)items gallery:(BOOL)gallery;
- (void)appendSuggestions:(NSArray *)items;
/* a row above the others, such as the bot's own button to continue elsewhere; nil title removes it */
- (void)setHeaderTitle:(NSString *)title handler:(void (^)(void))handler;
/* a spinner while the first answer is awaited, and a line when there is none */
- (void)setLoading:(BOOL)loading;
- (void)setEmptyText:(NSString *)text;
@property (nonatomic, readonly) NSUInteger count;
/* the height the rows want for a width, up to maxHeight */
- (CGFloat)preferredHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;

@end
