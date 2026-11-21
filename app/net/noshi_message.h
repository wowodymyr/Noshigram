#import <Foundation/Foundation.h>
@class UIImage;
#import "noshi_poll_model.h"

#import "noshi_bot_markup.h"

#include "noshi_messages.h"

@class NoshiRemoteFile;
@class NoshiStarGift;

/* the photo, sticker or file of a message, built off the main thread */
@interface NoshiMedia : NSObject {
    noshi_media_info _info;
    NSString *_name;
    NSString *_alt;
    NSString *_title;
    NSString *_performer;
    NSData *_waveformBars;
}

+ (NoshiMedia *)mediaWithInfo:(const noshi_media_info *)info;

@property (nonatomic, readonly) noshi_preview_kind kind;
@property (nonatomic, readonly) noshi_geo_point location;
@property (nonatomic, readonly) noshi_sticker_format stickerFormat;
/* the set a sticker belongs to, zero when its document does not name one by id */
@property (nonatomic, readonly) long long stickerSetId;
@property (nonatomic, readonly) long long stickerSetHash;
/* the sender hid the picture or the video under a spoiler */
@property (nonatomic, readonly) BOOL spoiler;
/* seconds the media lives after it is opened, zero for ordinary media; a one-time photo, video, voice note or round video carries NOSHI_VIEW_ONCE_TTL */
@property (nonatomic, readonly) int32_t ttlSeconds;
/* the time a photo was set, unix seconds, zero when it does not say */
@property (nonatomic, readonly) int32_t date;
/* the server removes it once the other side has opened it; the file is gone from the message afterwards */
@property (nonatomic, readonly) BOOL viewOnce;
/* the price in stars of paid media, zero for ordinary media; the media is locked while its kind is NOSHI_PREVIEW_PAID */
@property (nonatomic, readonly) long long paidStars;
/* a game emoji thrown into the chat: the result, zero while the server has not said (a message that is still being sent); its emoji is alt */
@property (nonatomic, readonly) int32_t diceValue;
@property (nonatomic, readonly) int32_t width;
@property (nonatomic, readonly) int32_t height;
@property (nonatomic, readonly) int32_t duration;
@property (nonatomic, readonly) long long size;
/* the file name, empty when the file has none */
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *mime;
/* the emoji a sticker stands for */
@property (nonatomic, readonly, copy) NSString *alt;
/* the tags of a song, empty when the file has none */
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *performer;
/* the bars of a voice note's waveform, one byte each from 0 to 31; nil when the note carries none */
@property (nonatomic, readonly, retain) NSData *waveformBars;
/* the file the bubble shows, and a smaller picture of it for while that loads; nil when there is nothing to fetch */
@property (nonatomic, readonly) NoshiRemoteFile *file;
@property (nonatomic, readonly) NoshiRemoteFile *previewFile;
/* the largest size of a photo, for the viewer; its bubble keeps the smaller file */
@property (nonatomic, readonly) NoshiRemoteFile *fullPhotoFile;
@property (nonatomic, readonly) long long fullPhotoSize;
/* what it takes to send this sticker again */
@property (nonatomic, readonly) noshi_media_ref ref;

@end

/* turns bounded core entities into text runs, dropping ranges outside the displayed UTF-16 text */
NSArray *NoshiTextEntities(NSString *text, const noshi_entity *entities, size_t count, const char *urls);

typedef enum {
    NoshiTextStyleBold,
    NoshiTextStyleItalic,
    NoshiTextStyleUnderline,
    NoshiTextStyleStrike,
    NoshiTextStyleCode,
    NoshiTextStyleLink,
    NoshiTextStyleMention,
    NoshiTextStyleHashtag,
    NoshiTextStyleCustomEmoji,
    NoshiTextStyleBotCommand,
    NoshiTextStyleSpoiler,
    NoshiTextStylePre,
    NoshiTextStyleQuote,
    NoshiTextStyleMentionName,
    NoshiTextStyleDate
} NoshiTextStyle;

/* a styled run of a message text; the range counts UTF-16 units */
@interface NoshiTextEntity : NSObject {
    NoshiTextStyle _style;
    NSRange _range;
    NSString *_url;
    long long _documentId;
    long long _userId;
    long long _accessHash;
    int32_t _date;
    uint8_t _flags;
}
@property (nonatomic, readonly) NoshiTextStyle style;
@property (nonatomic, readonly) NSRange range;
/* the address a link opens, nil when the text is the address or there is none */
@property (nonatomic, readonly, copy) NSString *url;
/* the document that draws a custom emoji, zero for every other style */
@property (nonatomic, assign) long long documentId;
/* a mention name: the user it opens, and the hash the server wants to accept it in a sent message */
@property (nonatomic, assign) long long userId;
@property (nonatomic, assign) long long accessHash;
/* a date: the moment, and the NOSHI_DATE_ shape bits; a quote: NOSHI_ENTITY_COLLAPSED in flags */
@property (nonatomic, assign) int32_t date;
@property (nonatomic, assign) uint8_t flags;
/* the language of a block of code, the address of a link and nothing else is kept in url */
- (id)initWithStyle:(NoshiTextStyle)style range:(NSRange)range url:(NSString *)url;
@end

typedef enum {
    NoshiMessageStateSent,
    NoshiMessageStateSending,
    NoshiMessageStateFailed
} NoshiMessageState;

typedef enum {
    NoshiOutgoingVoice,
    NoshiOutgoingRound,
    NoshiOutgoingPhoto,
    NoshiOutgoingVideo,
    NoshiOutgoingFile,
    NoshiOutgoingLocation,
    NoshiOutgoingContact
} NoshiOutgoingKind;

/* everything a send of a file or a point needs, kept with the pending message so a failed send can be tried again */
@interface NoshiOutgoing : NSObject {
@public
    NoshiOutgoingKind kind;
    int32_t replyTo;
    NSString *path;
    NSString *name;
    NSString *mime;
    NSString *phone;
    NSData *waveform;
    /* the text sent with a photo, a video or a file */
    NSString *caption;
    /* a photo or a video shown blurred until it is tapped */
    BOOL spoiler;
    /* a gif file that plays in the chat as an animation */
    BOOL animated;
    /* a photo or a video that is gone from the other side once it was opened */
    BOOL viewOnce;
    /* a file that is an audio file the server lists as a song: sent with this title and performer and the duration below, not forced to be a file */
    BOOL music;
    NSString *title;
    NSString *performer;
    int32_t durationMs;
    int32_t width;
    int32_t height;
    double latitude;
    double longitude;
    noshi_geo_point location;
    /* a copy made for the send, deleted once the server has it; a file the person chose is never deleted */
    BOOL temporary;
    /* a small picture of a photo or the first frame of a video, which the bubble shows while the file goes up and the server has none yet */
    UIImage *preview;
}
@end

@interface NoshiReaction : NSObject {
    noshi_reaction _row;
    NSArray *_faces;
}
+ (NoshiReaction *)reactionWithRow:(const noshi_reaction *)row;
/* the emoji that stand for custom emoji, by document id (NSNumber to NSString); a chip shows a placeholder until its id is here */
+ (void)rememberCustomTexts:(NSDictionary *)texts;
+ (BOOL)knowsCustomDocument:(long long)documentId;
@property (nonatomic, readonly) noshi_reaction row;
@property (nonatomic, readonly) NSString *emoji;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSString *displayText;
/* the entity that has a custom reaction drawn as its own picture over the emoji in displayText; nil for the other kinds and while the
   emoji it stands for is not known */
@property (nonatomic, readonly) NSArray *displayEntities;
@property (nonatomic, readonly) BOOL chosen;
@property (nonatomic, readonly) int32_t count;
/* the users the server's recent list names for this reaction, as NSNumbers, in list order */
@property (nonatomic, readonly) NSArray *reactorIds;
/* the people whose pictures stand on the chip in the place of the number (NoshiPerson items), set by the screen that knows who they
   are; nil keeps the number */
@property (nonatomic, retain) NSArray *faces;
/* what the faces are, as a string, so two chips with the same faces compare equal */
@property (nonatomic, readonly) NSString *faceKey;
@end

@interface NoshiMessage : NSObject {
    int32_t _messageId;
    int32_t _date;
    int32_t _replyTo;
    int32_t _replyStory;
    int32_t _replyPeerKind;
    long long _replyPeerId;
    NSString *_replyQuote;
    int32_t _topicId;
    int32_t _threadId;
    long long _fromId;
    long long _fromChannel;
    long long _targetId;
    int32_t _views;
    int32_t _forwards;
    BOOL _hasComments;
    int32_t _comments;
    long long _discussionId;
    NSArray *_commenters;
    long long _randomId;
    BOOL _outgoing;
    BOOL _noForwards;
    BOOL _invertMedia;
    BOOL _unreadMention;
    BOOL _mediaUnread;
    NSDate *_listenedDate;
    BOOL _spoilersRevealed;
    NSIndexSet *_expandedQuotes;
    BOOL _viewOnceOpened;
    BOOL _post;
    BOOL _forwarded;
    BOOL _edited;
    int _service;
    int32_t _serviceValue;
    long long _serviceCommunity;
    NoshiMessageState _state;
    float _uploadProgress;
    NSString *_text;
    NSString *_forwardName;
    NSString *_postAuthor;
    int32_t _forwardDate;
    long long _groupedId;
    long long _forwardKey;
    int32_t _forwardOriginKind;
    long long _forwardOriginId;
    int32_t _forwardOriginMessage;
    BOOL _savedOut;
    int32_t _savedPeerKind;
    long long _savedPeerId;
    int _callOutcome;
    BOOL _callVideo;
    NSString *_senderRank;
    NSArray *_entities;
    NoshiMedia *_media;
    NSString *_giftTitle;
    long long _giftStars;
    int32_t _giftNumber;
    NoshiStarGift *_gift;
    NSArray *_reactions;
    long long _viaBotId;
    int32_t _sendReplyTo;
    int32_t _sentAfterId;
    NSString *_sendQuote;
    int32_t _sendQuoteOffset;
    BOOL _sendSilent;
    long long _sendEffect;
    long long _effectId;
    NoshiMarkup *_markup;
    BOOL _reactionsPossible;
    BOOL _hasReactions;
    NoshiOutgoing *_pendingSend;
    UIImage *_localPoster;
    NoshiPoll *_poll;
}

/* nil for a message the screen cannot show */
+ (NoshiMessage *)messageWithRow:(const noshi_message_row *)row;
/* a message that only exists here until the server answers: the id is zero and the random id matches the answer */
/* a message that only exists here until its file or point is on the server; the file stays until then */
+ (NoshiMessage *)pendingOutgoing:(NoshiOutgoing *)outgoing randomId:(long long)randomId date:(int32_t)date;
/* what has to be sent for a pending message, nil for text and stickers */
@property (nonatomic, readonly, retain) NoshiOutgoing *pendingSend;
/* the first frame of a video of ours that the server has numbered but not yet given a thumbnail of, kept from the send so the bubble does not turn grey when the pending copy goes */
@property (nonatomic, retain) UIImage *localPoster;
/* what the bubble shows for a picture of ours while the server has none: the picture of the send, or the poster kept after it */
- (UIImage *)localPreview;
+ (NoshiMessage *)pendingText:(NSString *)text randomId:(long long)randomId date:(int32_t)date;
/* with the custom emoji entities the person typed, so the pending bubble draws them as the server's copy will */
+ (NoshiMessage *)pendingText:(NSString *)text entities:(NSArray *)entities randomId:(long long)randomId date:(int32_t)date;
+ (NoshiMessage *)pendingSticker:(NoshiMedia *)sticker randomId:(long long)randomId date:(int32_t)date;

/* zero while sending */
@property (nonatomic, assign) int32_t messageId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) BOOL noForwards;
/* the words stand above the picture, as the sender chose; the server's invert_media flag */
@property (nonatomic, readonly) BOOL invertMedia;
@property (nonatomic, readonly) int32_t replyTo;
/* the story this message answers, zero for none */
@property (nonatomic, readonly) int32_t replyStory;
@property (nonatomic, readonly) int32_t replyPeerKind;
@property (nonatomic, readonly) long long replyPeerId;
@property (nonatomic, readonly, copy) NSString *replyQuote;
/* the forum topic the message was written in; 1, General, for a message of a chat without topics too */
@property (nonatomic, readonly) int32_t topicId;
@property (nonatomic, readonly) int32_t threadId;
@property (nonatomic, readonly) long long fromId;
/* the channel a group message was written as, zero when a user wrote it */
@property (nonatomic, readonly) long long fromChannel;
/* a channel post's counters: how many saw it, zero when the server did not count */
@property (nonatomic, readonly) int32_t views;
@property (nonatomic, readonly) int32_t forwards;
/* the post has a comment thread; how many comments it has, the discussion group it lives in, and the user ids (NSNumber) of the
   newest commenters, at most three */
@property (nonatomic, readonly) BOOL hasComments;
@property (nonatomic, readonly) int32_t comments;
@property (nonatomic, readonly) long long discussionId;
@property (nonatomic, readonly, retain) NSArray *commenters;
/* names the sender in the people of a chat: the user id, or the channel id made negative so the two never meet; zero for none */
@property (nonatomic, readonly) long long senderKey;
@property (nonatomic, readonly) long long targetId;
@property (nonatomic, readonly) long long randomId;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) BOOL unreadMention;
/* a voice note or round video that nobody has played: this person for an incoming one, the other side for one of ours; the server clears it when it is played */
@property (nonatomic, assign) BOOL mediaUnread;
/* when this person played the incoming voice note on this phone, nil when not known; the server does not say it */
@property (nonatomic, retain) NSDate *listenedDate;
@property (nonatomic, readonly) BOOL post;
/* a message waiting to be sent into a broadcast channel looks like the post it will become: the channel writes it, not the account */
- (void)showAsChannelPost;
/* the person tapped the spoilers of this message open; kept here so a rebuilt layout does not cover them again */
@property (nonatomic, assign) BOOL spoilersRevealed;
/* the collapsed quotes the person opened, each named by the offset where its entity starts; kept here so a rebuilt layout does not fold them again */
@property (nonatomic, copy) NSIndexSet *expandedQuotes;
/* the person opened this one-time media on this phone; kept so the row reads as expired at once, before the server's edit of the message arrives */
@property (nonatomic, assign) BOOL viewOnceOpened;
@property (nonatomic, readonly) BOOL forwarded;
@property (nonatomic, readonly) BOOL edited;
/* an noshi_service_kind plus one, zero for an ordinary message */
@property (nonatomic, readonly) int service;
@property (nonatomic, assign) NoshiMessageState state;
/* how much of the file of a pending message the server has, from 0 to 1 */
@property (nonatomic, assign) float uploadProgress;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *forwardName;
/* the name a channel signs its posts with, empty when it does not sign or the message is no post */
@property (nonatomic, readonly, copy) NSString *postAuthor;
/* when the original of a forwarded message was written, zero when the header does not say */
@property (nonatomic, readonly) int32_t forwardDate;
/* the album the message belongs to: the photos and videos that were sent together share this number; zero for a
   message of its own */
@property (nonatomic, assign) long long groupedId;
/* who wrote a forwarded message, when the header says: the user id, or the negative of the channel id, as the people of a chat are keyed; zero when hidden */
@property (nonatomic, readonly) long long forwardKey;
/* where the header of a forwarded message says it stands: the peer kind (2 group, 3 channel), its id and the message in it; zero when the header names no place.
   The chat of the replies holds the comments of the account this way */
@property (nonatomic, readonly) int32_t forwardOriginKind;
@property (nonatomic, readonly) long long forwardOriginId;
@property (nonatomic, readonly) int32_t forwardOriginMessage;
- (void)placeInSavedMessagesOfUser:(long long)userId;
/* the words the server accepted for an edit of this message, shown at once with the mark of an edited one, before the copy it sends back is read */
- (void)noteEditedToText:(NSString *)text;
/* in the favorites, the chat the message came from: kind 1 user, 2 group, 3 channel, zero when the answer did not say */
@property (nonatomic, readonly) int32_t savedPeerKind;
@property (nonatomic, readonly) long long savedPeerId;
/* a call service message: how it ended (an noshi_call_outcome), and whether it had video; the length in seconds is serviceValue */
@property (nonatomic, readonly) int callOutcome;
@property (nonatomic, readonly) BOOL callVideo;
/* the custom title of an admin of a group, empty when there is none */
@property (nonatomic, readonly, copy) NSString *senderRank;
/* the number some service messages carry: a period, a duration, a count */
@property (nonatomic, readonly) int32_t serviceValue;
/* the community a chat was added to by a community service message, zero when it was taken out */
@property (nonatomic, readonly) long long serviceCommunity;
@property (nonatomic, readonly, retain) NSArray *entities;
@property (nonatomic, readonly, copy) NSArray *reactions;
@property (nonatomic, readonly) BOOL reactionsPossible;
/* a pending text answers this message when it goes out, zero for none; only a message that has not been sent uses it */
@property (nonatomic, assign) int32_t sendReplyTo;
/* the newest message the chat held when this one was written: the server's copy of a send has a number past it, an older message with the same words does not */
@property (nonatomic, assign) int32_t sentAfterId;
/* the words of the answered message that this reply quotes, and where they start in it; empty for a plain reply */
@property (nonatomic, copy) NSString *sendQuote;
@property (nonatomic, assign) int32_t sendQuoteOffset;
/* the message goes without a sound for the people who get it (silent in messages.sendMessage) */
@property (nonatomic, assign) BOOL sendSilent;
/* the effect the server says the message was sent with, zero for none */
@property (nonatomic, readonly) long long effectId;
/* the animated effect the message goes with (effect in messages.sendMessage), zero for none; only a private chat takes one */
@property (nonatomic, assign) long long sendEffect;
/* the bot whose inline result the message is, zero for any other */
@property (nonatomic, readonly) long long viaBotId;
/* the buttons under the message, or the keyboard it brought; nil without any */
@property (nonatomic, retain) NoshiMarkup *markup;
/* the message carries a reply markup that has not been read yet */
@property (nonatomic, readonly) BOOL hasMarkup;
/* a string that differs when what the buttons show differs, empty without markup */
@property (nonatomic, readonly) NSString *markupKey;
@property (nonatomic, readonly) BOOL hasReactions;
@property (nonatomic, readonly) NSString *reactionKey;
@property (nonatomic, readonly, retain) NoshiMedia *media;
/* the poll of a poll message, nil for any other and for a poll the reader could not use */
@property (nonatomic, retain) NoshiPoll *poll;
/* a string that differs when what the poll shows differs, empty without a poll */
@property (nonatomic, readonly) NSString *pollKey;
/* a gift service message: its name (empty for an unnamed catalog gift), its price in stars and, for a unique gift, its number */
@property (nonatomic, readonly, copy) NSString *giftTitle;
@property (nonatomic, readonly) long long giftStars;
@property (nonatomic, readonly) int32_t giftNumber;
/* the whole gift of a gift service message, nil when the action could not be read */
@property (nonatomic, readonly, retain) NoshiStarGift *gift;

@end

@interface NoshiSticker : NSObject {
    NoshiMedia *_media;
}
+ (NoshiSticker *)stickerWithRow:(const noshi_sticker_row *)row;
@property (nonatomic, readonly, retain) NoshiMedia *media;
@end

@interface NoshiStickerSet : NSObject {
    noshi_sticker_set_row _row;
    NSString *_title;
}
+ (NoshiStickerSet *)setWithRow:(const noshi_sticker_set_row *)row;
@property (nonatomic, readonly) noshi_sticker_set_row row;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) long long setId;
@property (nonatomic, readonly) NoshiRemoteFile *coverFile;
@end
