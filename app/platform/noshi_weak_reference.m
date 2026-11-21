#import "noshi_weak_reference.h"

#import <objc/runtime.h>

/* hangs on the target and is freed with it, which clears the reference: a block that outlives its screen then finds nil, where a pointer nobody cleared (a reference made in a method
   other than init, a callback handed to a strip that lives on) pointed at a freed screen and crashed on the first message it was sent */
@interface NoshiWeakSentinel : NSObject {
    NoshiWeakReference *_reference;
}
@property (nonatomic, readonly) NoshiWeakReference *reference;
- (id)initWithReference:(NoshiWeakReference *)reference;
@end

@implementation NoshiWeakSentinel

@synthesize reference = _reference;

- (id)initWithReference:(NoshiWeakReference *)reference {
    self = [super init];
    if (self) _reference = [reference retain];
    return self;
}

- (void)dealloc {
    [_reference clear];
    [_reference release];
    [super dealloc];
}

@end

static char NoshiWeakSentinelKey;

@implementation NoshiWeakReference

@synthesize target = _target;

/* one reference serves every holder of the same target: they are all cleared together when it goes, and nothing grows with each call */
+ (NoshiWeakReference *)referenceTo:(id)target {
    if (!target) return [[[NoshiWeakReference alloc] init] autorelease];
    @synchronized ([NoshiWeakReference class]) {
        NoshiWeakSentinel *sentinel = objc_getAssociatedObject(target, &NoshiWeakSentinelKey);
        if (sentinel) return sentinel.reference;
        NoshiWeakReference *reference = [[[NoshiWeakReference alloc] init] autorelease];
        reference->_target = target;
        sentinel = [[[NoshiWeakSentinel alloc] initWithReference:reference] autorelease];
        objc_setAssociatedObject(target, &NoshiWeakSentinelKey, sentinel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return reference;
    }
}

- (void)clear {
    _target = nil;
}

@end
