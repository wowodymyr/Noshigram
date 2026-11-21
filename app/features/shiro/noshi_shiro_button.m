#import "noshi_shiro_button.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_platform.h"
#import "noshi_shiro_controller.h"
#import "noshi_shiro_style.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

@interface NoshiShiroButton () {
    NoshiShiro *_shiro;
    NoshiWeakReference *_host;
}
@end

@implementation NoshiShiroButton

- (id)initWithShiro:(NoshiShiro *)shiro host:(UIViewController *)host {
    self = [super initWithFrame:CGRectMake(0, 0, 54, 28)];
    if (!self) return nil;
    _shiro = [shiro retain];
    _host = [[NoshiWeakReference referenceTo:host] retain];
    [self setTitle:NSLocalizedString(@"shiro.button", nil) forState:UIControlStateNormal];
    self.accessibilityLabel = NSLocalizedString(@"shiro.button.accessibility", nil);
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 1.5;
    self.titleLabel.font = NoshiShiroFontBody(14, YES);
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:NoshiShiroStateDidChangeNotification object:shiro];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:NoshiThemeDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_host clear];
    [_host release];
    [_shiro release];
    [super dealloc];
}

- (CGSize)preferredSize {
    return CGSizeMake(54, 28);
}

- (void)refresh {
    NoshiShiroState state = _shiro.state;
    BOOL lit = state == NoshiShiroStateUp;
    BOOL working = state == NoshiShiroStateRegistering || state == NoshiShiroStateConnecting;
    UIColor *accent = NoshiColorAccent();
    UIColor *quiet = [accent colorWithAlphaComponent:0.5f];
    /* the accent of the theme: solid while the tunnel carries the traffic, an outline while it dials, a paler outline when it is off or has failed */
    self.backgroundColor = lit ? accent : [UIColor clearColor];
    self.layer.borderColor = (lit || working ? accent : quiet).CGColor;
    [self setTitleColor:lit ? [UIColor whiteColor] : (working ? accent : quiet) forState:UIControlStateNormal];
}

- (void)open {
    UIViewController *host = _host.target;
    if (host) [NoshiShiroController presentWithShiro:_shiro from:host];
}

@end

@interface NoshiShiroBarItem () {
    NoshiShiro *_shiro;
    NoshiWeakReference *_host;
}
@end

@implementation NoshiShiroBarItem

- (id)initWithShiro:(NoshiShiro *)shiro host:(UIViewController *)host {
    self = [super initWithTitle:NSLocalizedString(@"shiro.button", nil) style:UIBarButtonItemStyleBordered target:nil action:NULL];
    if (!self) return nil;
    _shiro = [shiro retain];
    _host = [[NoshiWeakReference referenceTo:host] retain];
    self.target = self;
    self.action = @selector(open);
    self.accessibilityLabel = NSLocalizedString(@"shiro.button.accessibility", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:NoshiShiroStateDidChangeNotification object:shiro];
    /* the lit button wears the accent, which changes with the theme and the color of your own */
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:NoshiThemeDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_host clear];
    [_host release];
    [_shiro release];
    [super dealloc];
}

- (void)refresh {
    switch (_shiro.state) {
    case NoshiShiroStateUp: self.tintColor = NoshiColorAccent(); break;
    case NoshiShiroStateRegistering:
    case NoshiShiroStateConnecting: self.tintColor = [UIColor colorWithRed:0.80f green:0.55f blue:0.08f alpha:1]; break;
    default: self.tintColor = nil; break;
    }
}

- (void)open {
    UIViewController *host = _host.target;
    if (host) [NoshiShiroController presentWithShiro:_shiro from:host];
}

@end
