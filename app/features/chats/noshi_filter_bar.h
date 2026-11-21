#import <UIKit/UIKit.h>

#import "noshi_chat_settings.h"

@class NoshiFilterBar;

@protocol NoshiFilterBarDelegate <NSObject>
- (void)filterBar:(NoshiFilterBar *)bar didSelectIndex:(NSInteger)index;
@end

/* a row of pill buttons that scrolls sideways, one selected, each with an optional unread count */
@interface NoshiFilterBar : UIView {
    id<NoshiFilterBarDelegate> _delegate;
    NSInteger _selectedIndex;
}

@property (nonatomic, assign) id<NoshiFilterBarDelegate> delegate;
@property (nonatomic, assign) NSInteger selectedIndex;

- (id)initWithTitles:(NSArray *)titles;
- (void)setEntities:(NSArray *)entities forIndex:(NSInteger)index;
- (void)redrawTitles;
- (void)setCount:(NSInteger)count forIndex:(NSInteger)index;
/* the name of the icon of a tab (see NoshiFolderIconName); a tab with none shows only its name whatever the style */
- (void)setIconName:(NSString *)name forIndex:(NSInteger)index;
/* what the tabs show; animated moves the tabs to their new widths and fades the name and the icon in or out, as exteraGram does when the setting changes */
@property (nonatomic, assign) NoshiFolderTabStyle tabStyle;
- (void)setTabStyle:(NoshiFolderTabStyle)style animated:(BOOL)animated;

@end
