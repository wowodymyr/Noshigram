#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_message.h"
#import "noshi_session.h"

#include "noshi_stories.h"

/* one story as the viewer draws it; built off the main thread */
@class NoshiPerson;

/* who sees a story we publish: a base choice, with the people a chosen list holds or the ones left out of everyone or the contacts */
@interface NoshiStoryAudience : NSObject {
    noshi_story_privacy _base;
    NSArray *_allowed;
    NSArray *_denied;
}
+ (NoshiStoryAudience *)audienceWithBase:(noshi_story_privacy)base;
@property (nonatomic, assign) noshi_story_privacy base;
/* NoshiPerson, the people of a chosen list (base NOSHI_STORY_SELECTED) */
@property (nonatomic, copy) NSArray *allowed;
/* NoshiPerson, the people left out (base everyone or contacts) */
@property (nonatomic, copy) NSArray *denied;
/* the C form the requests take; at most NOSHI_STORY_USERS_MAX people of each list, and only those with an access hash */
- (void)fillAudience:(noshi_story_audience *)out;
@end

@interface NoshiStory : NSObject {
    noshi_story_row _row;
    NSString *_caption;
    NoshiMedia *_media;
    NoshiMedia *_music;
    NoshiReaction *_reaction;
}
+ (NoshiStory *)storyWithRow:(const noshi_story_row *)row;
@property (nonatomic, readonly) int32_t storyId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) int32_t expireDate;
@property (nonatomic, readonly) int32_t views;
/* how many reactions the story has gathered */
@property (nonatomic, readonly) int32_t reactions;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) BOOL pinned;
@property (nonatomic, readonly) BOOL closeFriends;
/* the poster closed it to forwarding, so it can neither be sent on nor saved */
@property (nonatomic, readonly) BOOL noForwards;
/* who sees it; a story shown to a chosen list reads as its nearest audience and is kept as it is unless the person picks another */
@property (nonatomic, readonly) noshi_story_privacy privacy;
@property (nonatomic, readonly) BOOL selectedAudience;
@property (nonatomic, readonly, copy) NSString *caption;
/* a picture or a video; kind says which */
@property (nonatomic, readonly, retain) NoshiMedia *media;
/* the track that plays with the story, nil when it has none */
@property (nonatomic, readonly, retain) NoshiMedia *music;
/* "PERFORMER · TITLE" for the label of the track, whichever of the two the tags have */
@property (nonatomic, readonly) NSString *musicLine;
/* our reaction to it, nil when there is none */
@property (nonatomic, readonly, retain) NoshiReaction *reaction;
@end

/* one ring of the strip: a poster and how much of their stories is unseen */
@interface NoshiStoryPeer : NSObject {
    NoshiDialog *_owner;
    int32_t _maxReadId;
    int32_t _count;
    int32_t _unread;
    int32_t _newestDate;
    int32_t _firstUnreadId;
    BOOL _closeFriends;
}
+ (NoshiStoryPeer *)peerWithRow:(const noshi_story_peer *)row;
/* a poster whose stories are already in hand, with nothing unseen */
+ (NoshiStoryPeer *)peerWithOwner:(NoshiDialog *)owner count:(int32_t)count;
/* the poster in the form every chat screen uses, which also names them to requests */
@property (nonatomic, readonly, retain) NoshiDialog *owner;
@property (nonatomic, readonly) int32_t maxReadId;
@property (nonatomic, readonly) int32_t count;
@property (nonatomic, readonly) int32_t unread;
@property (nonatomic, readonly) int32_t newestDate;
@property (nonatomic, readonly) int32_t firstUnreadId;
/* an unseen story is for close friends only, which turns the ring green */
@property (nonatomic, readonly) BOOL closeFriends;
@end

/* the answer of a story list: the poster with the current seen mark, and the stories oldest first */
typedef void (^NoshiStoriesCompletion)(NoshiStoryPeer *peer, NSArray *stories, NSString *errorName);

/* stories: the strip, one poster's stories, the seen mark, reactions and replies; implemented in
   noshi_session_stories.m */
@interface NoshiSession (Stories)

/* NoshiStoryPeer items, own stories first, then the unseen posters, then the seen ones */
- (void)loadStoryPeers:(NoshiListCompletion)completion;
/* the live stories of one user or channel; a story the server sent only as a header is fetched in full first */
- (void)loadStoriesOfDialog:(NoshiDialog *)dialog completion:(NoshiStoriesCompletion)completion;
/* marks everything up to storyId seen, and counts the view; a failure only shows in the log, the next open says it again */
- (void)markStoriesSeenOfDialog:(NoshiDialog *)dialog upTo:(int32_t)storyId;
/* a page of the people who looked at one of our stories, newest first: each item holds @"peer" (the user id), @"date", @"blocked" and, when they reacted, @"reaction" (an NoshiReaction); people is keyed by user id as the other lists are,
   next is the offset of the following page or nil at the end, total the whole count of views, reactions the whole count of reactions */
- (void)loadViewersOfStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog offset:(NSString *)offset
                completion:(void (^)(NSArray *items, NSDictionary *people, NSString *next, int32_t total, int32_t reactions, NSString *errorName))completion;
/* a nil reaction takes ours back */
- (void)reactToStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog reaction:(NoshiReaction *)reaction
          completion:(void (^)(NSString *errorName))completion;
/* the text goes to the poster's chat as a reply to the story; randomId must differ for every message */
- (void)replyToStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog text:(NSString *)text randomId:(long long)randomId
          completion:(void (^)(NSString *errorName))completion;
/* sends the story of owner into the chat target as a message that opens it; the completion is the one of a send, with the id of the new message */
- (void)forwardStory:(int32_t)storyId ofDialog:(NoshiDialog *)owner toDialog:(NoshiDialog *)target randomId:(long long)randomId
          completion:(NoshiSendCompletion)completion;

/* the public address of one story, from the server; the completion gets the link or an error name */
- (void)loadLinkOfStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *link, NSString *errorName))completion;
/* hidden takes the stories of the poster out of the strip into the archive section of the other clients, and false brings them back */
- (void)setStoriesOfDialog:(NoshiDialog *)dialog hidden:(BOOL)hidden completion:(void (^)(NSString *errorName))completion;

/* our own pinned stories, newest first, and one page of our archive of expired ones before beforeId (zero for the newest);
   NoshiStory items, empty on the last page */
- (void)loadPinnedStories:(NoshiListCompletion)completion;

/* the management of our own stories; the completion runs on the main thread with the error name or nil */
/* a nil caption leaves the text as it is, an empty one takes it off; a nil privacy leaves the audience as it is */
- (void)editStory:(int32_t)storyId caption:(NSString *)caption privacy:(NSNumber *)privacy completion:(void (^)(NSString *errorName))completion;
/* the same with an audience that may name people; a nil audience leaves it alone */
- (void)editStory:(int32_t)storyId caption:(NSString *)caption audience:(NoshiStoryAudience *)audience completion:(void (^)(NSString *errorName))completion;
- (void)deleteStory:(int32_t)storyId completion:(void (^)(NSString *errorName))completion;
/* pinned keeps it on the profile after the day, otherwise it only stays in the archive */
- (void)setStory:(int32_t)storyId pinned:(BOOL)pinned completion:(void (^)(NSString *errorName))completion;
- (void)loadStoryArchiveBefore:(int32_t)beforeId completion:(NoshiListCompletion)completion;

@end
