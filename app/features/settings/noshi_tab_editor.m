#import "noshi_tab_editor.h"

#import "noshi_alert.h"
#import "noshi_chat_settings.h"
#import "noshi_tab_bar.h"
#import "noshi_weak_reference.h"

@interface NoshiTabEditor () <NoshiTabBarDelegate> {
    int _order[NOSHI_TAB_SLOTS];
    NSInteger _selected;
    NSInteger _dragFrom;
    BOOL _applied;
    NoshiTabBar *_preview;
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiTabEditor

- (id)init {
    self = [super init];
    if (!self) return nil;
    NoshiTabOrderLoad(_order);
    _dragFrom = -1;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"tabedit.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _preview.delegate = nil;
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (_applied && self.isMovingFromParentViewController) {
        _applied = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiTabOrderDidChangeNotification object:nil];
        });
    }
}

- (void)themeDidChange { [self rebuild]; }

- (void)tabBar:(NoshiTabBar *)tabBar didSelectIndex:(NSInteger)index {
    (void)tabBar;
    _selected = index;
    [self rebuild];
}

- (void)dragged:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:_preview];
    CGFloat width = _preview.bounds.size.width;
    if (width <= 0) return;
    NSInteger slot = MIN(NOSHI_TAB_SLOTS - 1, MAX(0, (NSInteger)(point.x * NOSHI_TAB_SLOTS / width)));
    if (gesture.state == UIGestureRecognizerStateBegan) _dragFrom = slot;
    else if (gesture.state == UIGestureRecognizerStateEnded) {
        if (_dragFrom >= 0 && noshi_tab_order_move(_order, (size_t)_dragFrom, (size_t)slot)) _selected = slot;
        _dragFrom = -1;
        [self rebuild];
    } else if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) _dragFrom = -1;
}

- (void)rebuild {
    static NSString *const keys[] = {@"tab.chats", @"tab.contacts", @"tab.settings", @"tab.profile", @"tab.calls"};
    static const NoshiSymbol symbols[] = {NoshiSymbolChats, NoshiSymbolPerson, NoshiSymbolGear, NoshiSymbolSmiley, NoshiSymbolPhone};
    NoshiWeakReference *weak = _weak;
    NSMutableArray *titles = [NSMutableArray array], *icons = [NSMutableArray array];
    for (NSUInteger i = 0; i < NOSHI_TAB_SLOTS; ++i) {
        [titles addObject:NSLocalizedString(keys[_order[i]], nil)];
        [icons addObject:[NSNumber numberWithInt:symbols[_order[i]]]];
    }
    _preview.delegate = nil;
    [_preview release];
    _preview = [[NoshiTabBar alloc] initWithTitles:titles symbols:icons];
    _preview.delegate = self;
    _preview.selectedIndex = _selected;
    UILongPressGestureRecognizer *drag = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)] autorelease];
    [_preview addGestureRecognizer:drag];
    NoshiSettingsRow *preview = [NoshiSettingsRow viewRowWithView:_preview height:^CGFloat(CGFloat width) { (void)width; return [NoshiTabBar barHeight]; }];
    NSMutableArray *choices = [NSMutableArray array];
    for (int kind = 0; kind < NOSHI_TAB_KINDS; ++kind) {
        int selectedKind = kind;
        [choices addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString(keys[kind], nil) subtitle:nil checked:_order[_selected] == kind tap:^{
            NoshiTabEditor *editor = weak.target;
            if (!editor) return;
            if (!noshi_tab_order_replace(editor->_order, (size_t)editor->_selected, selectedKind)) {
                NoshiShowNotice(nil, NSLocalizedString(@"tabedit.required", nil));
                return;
            }
            [editor rebuild];
        }]];
    }
    NoshiSettingsRow *save = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolCheckMark() title:NSLocalizedString(@"tabedit.apply", nil) destructive:NO tap:^{
        NoshiTabEditor *editor = weak.target;
        if (!editor) return;
        if (!NoshiTabOrderStore(editor->_order)) {
            NoshiShowNotice(nil, NSLocalizedString(@"tabedit.required", nil));
            return;
        }
        editor->_applied = YES;
        [editor goBack];
    }];
    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tabedit.preview", nil) footer:NSLocalizedString(@"tabedit.info", nil) rows:[NSArray arrayWithObject:preview]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tabedit.choose", nil) footer:nil rows:choices],
        [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:save]], nil];
    [self reloadSettings];
}

@end
