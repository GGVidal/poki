#import "PBHelper.h"
#import <XCTest/XCTest.h>
#import <objc/message.h>
#import <dlfcn.h>

@implementation PBHelper

+ (id)ax {
    id device = [XCUIDevice sharedDevice];
    SEL s = NSSelectorFromString(@"accessibilityInterface");
    return [device respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(device, s) : nil;
}

+ (NSNumber *)requestBackgroundAssertionForPID:(int)pid {
    Class cls = NSClassFromString(@"XCTRunnerDaemonSession");
    id session = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedSession"));
    id proxy = ((id (*)(id, SEL))objc_msgSend)(session, NSSelectorFromString(@"daemonProxy"));
    SEL s = NSSelectorFromString(@"_XCT_requestBackgroundAssertionForPID:reply:");
    if (!proxy || ![proxy respondsToSelector:s]) return nil;
    __block NSNumber *granted = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    ((void (*)(id, SEL, int, void (^)(BOOL)))objc_msgSend)(proxy, s, pid, ^(BOOL ok) { granted = @(ok); dispatch_semaphore_signal(sem); });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    return granted;
}

+ (NSArray *)attributes {
    NSArray *keyPaths = @[@"elementType", @"identifier", @"label", @"value", @"frame", @"children"];
    Class snap = NSClassFromString(@"XCElementSnapshot");
    SEL m = NSSelectorFromString(@"axAttributesForElementSnapshotKeyPaths:isMacOS:");
    if ([snap respondsToSelector:m]) {
        id mapped = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(snap, m, keyPaths, NO);
        if ([mapped isKindOfClass:NSSet.class]) mapped = [(NSSet *)mapped allObjects];
        if ([mapped isKindOfClass:NSArray.class] && [mapped count]) return mapped;
    }
    return keyPaths;
}

+ (id)snapshotForPID:(int)pid timeout:(NSTimeInterval)seconds status:(NSString **)status {
    return [self snapshotForPID:pid depth:40 timeout:seconds status:status];
}

+ (id)snapshotForPID:(int)pid depth:(NSInteger)depth timeout:(NSTimeInterval)seconds status:(NSString **)status {
    id ax = [self ax];
    Class elCls = NSClassFromString(@"XCAccessibilityElement");
    SEL e = NSSelectorFromString(@"elementWithProcessIdentifier:");
    if (!ax || ![elCls respondsToSelector:e]) { if (status) *status = @"api unavailable"; return nil; }
    id element = ((id (*)(id, SEL, int))objc_msgSend)(elCls, e, pid);
    SEL s = NSSelectorFromString(@"requestSnapshotForElement:attributes:parameters:error:");
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    SEL d = NSSelectorFromString(@"defaultParameters");
    if ([ax respondsToSelector:d]) { id def = ((id (*)(id, SEL))objc_msgSend)(ax, d); if ([def isKindOfClass:NSDictionary.class]) [params addEntriesFromDictionary:def]; }
    params[@"maxDepth"] = @(depth); params[@"maxChildren"] = @400; params[@"maxArrayCount"] = @400; params[@"traverseFromParentsToChildren"] = @YES;
    NSArray *attributes = [self attributes];
    __block id result = nil; __block NSString *why = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            NSError *err = nil;
            result = ((id (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(ax, s, element, attributes, params, &err);
            if (!result) why = [NSString stringWithFormat:@"error: %@", err];
        } @catch (NSException *x) { why = [NSString stringWithFormat:@"exception %@: %@", x.name, x.reason]; }
        dispatch_semaphore_signal(sem);
    });
    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC))) != 0) {
        if (status) *status = [NSString stringWithFormat:@"timeout after %.0f s", seconds];
        return nil;
    }
    if (!result) { if (status) *status = why ?: @"nil"; return nil; }
    id root = nil;
    @try { root = [result valueForKey:@"_rootElementSnapshot"]; } @catch (__unused NSException *x) {}
    if (status) *status = @"ok";
    return root ?: result;
}

// Same request, made synchronously on the calling (main) thread, like Poki's own reads.
+ (id)snapshotOnCallerForPID:(int)pid status:(NSString **)status {
    id ax = [self ax];
    Class elCls = NSClassFromString(@"XCAccessibilityElement");
    id element = ((id (*)(id, SEL, int))objc_msgSend)(elCls, NSSelectorFromString(@"elementWithProcessIdentifier:"), pid);
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    SEL d = NSSelectorFromString(@"defaultParameters");
    if ([ax respondsToSelector:d]) { id def = ((id (*)(id, SEL))objc_msgSend)(ax, d); if ([def isKindOfClass:NSDictionary.class]) [params addEntriesFromDictionary:def]; }
    NSError *err = nil; id result = nil;
    @try { result = ((id (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(ax, NSSelectorFromString(@"requestSnapshotForElement:attributes:parameters:error:"), element, [self attributes], params, &err); }
    @catch (NSException *x) { if (status) *status = [NSString stringWithFormat:@"exception %@", x.reason]; return nil; }
    if (!result) { if (status) *status = [NSString stringWithFormat:@"error: %@", err]; return nil; }
    id root = nil; @try { root = [result valueForKey:@"_rootElementSnapshot"]; } @catch (__unused NSException *x) {}
    if (status) *status = @"ok";
    return root ?: result;
}

// -[XCAXClient_iOS setAttribute:(NSString *)value:element:outError:] (B48@0:8@"NSString"16@24@"XCAccessibilityElement"32^@40).
+ (BOOL)setAttribute:(NSString *)name value:(id)value onSnapshot:(id)snapshot error:(NSString **)error {
    id ax = [self ax];
    id element = nil;
    @try { element = [snapshot valueForKey:@"accessibilityElement"]; } @catch (__unused NSException *x) {}
    SEL s = NSSelectorFromString(@"setAttribute:value:element:outError:");
    if (!element || ![ax respondsToSelector:s]) { if (error) *error = @"no element or selector"; return NO; }
    NSError *err = nil; BOOL ok = NO;
    @try { ok = ((BOOL (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(ax, s, name, value, element, &err); }
    @catch (NSException *x) { if (error) *error = [NSString stringWithFormat:@"exception %@: %@", x.name, x.reason]; return NO; }
    if (error) *error = err ? err.description : @"none";
    return ok;
}

// Read action constants straight out of the phone's own AXRuntime by symbol name.
+ (NSString *)axRuntimeConstants {
    void *h = dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW);
    if (!h) return [NSString stringWithFormat:@"dlopen failed: %s", dlerror()];
    NSArray *names = @[@"kAXPressAction", @"kAXEscapeAction", @"kAXActivateAction", @"kAXShowMenuAction", @"kAXShowAlternateUIAction",
        @"kAXScrollToVisibleAction", @"kAXIncrementAction", @"kAXDecrementAction", @"kAXScrollDownPageAction", @"kAXScrollUpPageAction",
        @"kAXScrollLeftPageAction", @"kAXScrollRightPageAction", @"kAXScrollDownByPageAction", @"kAXScrollUpByPageAction",
        @"kAXScrollLeftByPageAction", @"kAXScrollRightByPageAction", @"kAXMagicTapAction", @"kAXZoomInAction", @"kAXZoomOutAction",
        @"kAXDismissAction", @"kAXSelectAction", @"kAXPickAction", @"kAXCancelAction", @"kAXDefaultAction", @"kAXBackAction",
        @"kAXPerformEscapeAction", @"kAXAccessibilityEscapeAction", @"kAXCustomAction", @"kAXActivateCustomAction",
        @"kAXScrollToTopAction", @"kAXScrollToBottomAction", @"kAXLongPressAction", @"kAXDoubleTapAction", @"kAXTwoFingerDoubleTapAction",
        @"kAXBeginMonitoringIdleRunLoopAction", @"kAXDetectAnimationsNonActiveAction", @"kAXIncrementAction_iOS", @"kAXDecrementAction_iOS"];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        void *p = dlsym(h, n.UTF8String);
        if (p) [out addObject:[NSString stringWithFormat:@"%@=%d", n, *(int *)p]];
    }
    return [out componentsJoinedByString:@" "];
}

+ (NSString *)describeAction:(NSInteger)action {
    id a = ((id (*)(id, SEL, NSInteger))objc_msgSend)([NSClassFromString(@"XCUIAccessibilityAction") alloc], NSSelectorFromString(@"initWithAXAction:"), action);
    return [a description] ?: @"nil";
}

// AccessibilityUtilities' assistive-client element (the layer VoiceOver uses).
+ (NSString *)axElementRoute:(NSString *)route onSnapshot:(id)snapshot {
    static void *h; if (!h) h = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
    if (!h) return [NSString stringWithFormat:@"dlopen failed %s", dlerror()];
    id xcel = nil; @try { xcel = [snapshot valueForKey:@"accessibilityElement"]; } @catch (__unused NSException *x) {}
    if (!xcel) return @"no accessibilityElement";
    id axui = ((id (*)(id, SEL))objc_msgSend)(xcel, NSSelectorFromString(@"AXUIElement"));
    if (!axui) return @"no AXUIElement";
    Class AXElement = NSClassFromString(@"AXElement");
    id el = ((id (*)(id, SEL, id))objc_msgSend)(AXElement, NSSelectorFromString(@"elementWithAXUIElement:"), axui);
    if (!el) return @"no AXElement";
    unsigned ctx = 0, disp = 0;
    @try {
        ctx = ((unsigned (*)(id, SEL))objc_msgSend)(el, NSSelectorFromString(@"windowContextId"));
        disp = ((unsigned (*)(id, SEL))objc_msgSend)(el, NSSelectorFromString(@"windowDisplayId"));
    } @catch (__unused NSException *x) {}
    NSString *result = @"?";
    @try {
        if ([route isEqualToString:@"press"]) {
            BOOL ok = ((BOOL (*)(id, SEL))objc_msgSend)(el, NSSelectorFromString(@"press"));
            result = ok ? @"press returned YES" : @"press returned NO";
        } else if ([route isEqualToString:@"tap"]) {
            ((void (*)(id, SEL, unsigned long))objc_msgSend)(el, NSSelectorFromString(@"simulateTapWithFingerIndex:"), 0);
            result = @"simulateTap sent";
        }
    } @catch (NSException *x) { result = [NSString stringWithFormat:@"exception %@: %@", x.name, x.reason]; }
    return [NSString stringWithFormat:@"%@ | windowContextId=%u displayId=%u", result, ctx, disp];
}

+ (void)loadAXU { static void *h; if (!h) h = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW); }

// Names of hand event types straight from the system's own debug describer.
+ (NSString *)handTypeNames {
    [self loadAXU];
    NSString *(*desc)(unsigned) = dlsym(RTLD_DEFAULT, "_AXDebugDescriptionForAXHandEventType");
    if (!desc) desc = dlsym(RTLD_DEFAULT, "AXDebugDescriptionForAXHandEventType");
    if (!desc) return @"describer not found";
    NSMutableArray *o = [NSMutableArray array];
    for (unsigned i = 0; i < 24; i++) { NSString *d = desc(i); if (d.length) [o addObject:[NSString stringWithFormat:@"%u=%@", i, d]]; }
    return [o componentsJoinedByString:@" "];
}

+ (unsigned)contextIdOfSnapshot:(id)snapshot {
    [self loadAXU];
    id xcel = nil; @try { xcel = [snapshot valueForKey:@"accessibilityElement"]; } @catch (__unused NSException *x) {}
    id axui = xcel ? ((id (*)(id, SEL))objc_msgSend)(xcel, NSSelectorFromString(@"AXUIElement")) : nil;
    id el = axui ? ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"AXElement"), NSSelectorFromString(@"elementWithAXUIElement:"), axui) : nil;
    return el ? ((unsigned (*)(id, SEL))objc_msgSend)(el, NSSelectorFromString(@"windowContextId")) : 0;
}

// A touch down + up built as AXEventRepresentation with an explicit context id, pid and display id,
// posted through AXBackBoardServer.
+ (NSString *)postTapAt:(CGPoint)p contextId:(unsigned)ctx pid:(int)pid displayId:(unsigned)display down:(int)down up:(int)up {
    [self loadAXU];
    Class Rep = NSClassFromString(@"AXEventRepresentation");
    id server = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"AXBackBoardServer"), NSSelectorFromString(@"server"));
    if (!Rep || !server) return @"classes missing";
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *type in @[@(down), @(up)]) {
        id rep = ((id (*)(id, SEL, unsigned, CGPoint))objc_msgSend)(Rep, NSSelectorFromString(@"touchRepresentationWithHandType:location:"), type.unsignedIntValue, p);
        if (!rep) { [out addObject:@"nil rep"]; continue; }
        if (ctx) ((void (*)(id, SEL, unsigned))objc_msgSend)(rep, NSSelectorFromString(@"setContextId:"), ctx);
        if (pid > 0) ((void (*)(id, SEL, int))objc_msgSend)(rep, NSSelectorFromString(@"setPid:"), pid);
        if (display) ((void (*)(id, SEL, unsigned))objc_msgSend)(rep, NSSelectorFromString(@"setDisplayId:"), display);
        @try { ((void (*)(id, SEL, id, BOOL))objc_msgSend)(server, NSSelectorFromString(@"postEvent:systemEvent:"), rep, NO); [out addObject:[NSString stringWithFormat:@"posted type %@", type]]; }
        @catch (NSException *x) { [out addObject:[NSString stringWithFormat:@"exception %@", x.reason]]; }
        usleep(80000);
    }
    return [out componentsJoinedByString:@", "];
}

+ (BOOL)pressSnapshot:(id)snapshot action:(NSInteger)action error:(NSString **)error {
    id ax = [self ax];
    id element = nil;
    @try { element = [snapshot valueForKey:@"accessibilityElement"]; } @catch (__unused NSException *x) {}
    SEL s = NSSelectorFromString(@"performAction:onElement:value:error:");
    if (!element || ![ax respondsToSelector:s]) { if (error) *error = @"no element or selector"; return NO; }
    NSError *err = nil; BOOL ok = NO;
    // The first argument is an XCUIAccessibilityAction (encoding B48@0:8@"XCUIAccessibilityAction"16@"XCAccessibilityElement"24@32^@40).
    id actionObject = ((id (*)(id, SEL, NSInteger))objc_msgSend)([NSClassFromString(@"XCUIAccessibilityAction") alloc], NSSelectorFromString(@"initWithAXAction:"), action);
    @try { ok = ((BOOL (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(ax, s, actionObject, element, nil, &err); }
    @catch (NSException *x) { if (error) *error = [NSString stringWithFormat:@"exception %@: %@", x.name, x.reason]; return NO; }
    if (error) *error = err ? err.description : @"none";
    return ok;
}
@end
