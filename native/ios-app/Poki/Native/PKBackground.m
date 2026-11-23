// Experimental (issue #656). See PKBackground.h. Everything goes through testmanagerd (the session
// Poki already holds), which is the route that works on a phone; nothing here talks to an app's
// accessibility server directly, and nothing synthesizes a touch.
#if POKI_EXPERIMENTS
#import "PKBackground.h"
#import "InProcess.h"

@interface PKInProcess (Background)
- (nullable id)backgroundSession;
- (nullable id)backgroundAccessibility;
- (int)backgroundPIDForBundle:(NSString *)bundle;
- (nullable id)backgroundSnapshotForPID:(int)pid code:(NSString **)code;
@end
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

@interface PKBackgroundElement ()
@property (nonatomic, readwrite) NSInteger index;
@property (nonatomic, readwrite) NSUInteger type;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite) BOOL selected;
@property (nonatomic, readwrite) CGRect frame;
@property (nonatomic, readwrite, copy) NSString *value;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *actions;
@property (nonatomic, strong) id snapshot;
@end
@implementation PKBackgroundElement
@end

@interface PKBackgroundOutcome ()
@property (nonatomic, readwrite) BOOL background;
@property (nonatomic, readwrite) BOOL needsFront;
@property (nonatomic, readwrite, copy, nullable) NSString *failure;
@end
@implementation PKBackgroundOutcome
+ (instancetype)ok { PKBackgroundOutcome *o = [self new]; o.background = YES; return o; }
+ (instancetype)front:(NSString *)why { PKBackgroundOutcome *o = [self new]; o.needsFront = YES; o.failure = why; return o; }
+ (instancetype)failed:(NSString *)why { PKBackgroundOutcome *o = [self new]; o.failure = why; return o; }
@end

static id PKBGSend(id target, NSString *selector) {
    SEL s = NSSelectorFromString(selector);
    return [target respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(target, s) : nil;
}

@implementation PKBackground {
    NSMutableDictionary<NSString *, NSNumber *> *_held;
    NSMutableDictionary<NSString *, NSNumber *> *_known;
}

+ (instancetype)shared {
    static PKBackground *shared; static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [PKBackground new]; shared->_held = [NSMutableDictionary dictionary]; shared->_known = [NSMutableDictionary dictionary]; });
    return shared;
}

- (id)daemonProxy {
    // Poki's own session: XCTest's shared one is not the session Poki opened.
    id session = [[PKInProcess shared] backgroundSession];
    return session ? PKBGSend(session, @"daemonProxy") : nil;
}

- (id)axClient {
    return [[PKInProcess shared] backgroundAccessibility];
}

/// Poki's in-process session is not a UI test, so XCUIApplication is off limits (it raises "Device is
/// not configured for UI testing"). The pid comes from Poki's own reads of the app while it was in
/// front, and the element from the pid.
- (void)remember:(NSString *)bundleID pid:(int)pid {
    if (bundleID.length == 0 || pid <= 0) return;
    @synchronized (self) { if (_known[bundleID].intValue != pid) { _known[bundleID] = @(pid); [_held removeObjectForKey:bundleID]; } }
}

- (int)knownPid:(NSString *)bundleID {
    int pid;
    @synchronized (self) { pid = _known[bundleID].intValue; }
    if (pid <= 0) pid = [[PKInProcess shared] backgroundPIDForBundle:bundleID];
    if (pid <= 0) return 0;
    @synchronized (self) { _known[bundleID] = @(pid); }
    // The pid is checked against the bundle each time: a relaunched app has a new one.
    id proxy = [self daemonProxy];
    SEL s = NSSelectorFromString(@"_XCT_requestBundleIDForPID:reply:");
    if (![proxy respondsToSelector:s]) return pid;
    __block NSString *found = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    ((void (*)(id, SEL, int, void (^)(NSString *, NSError *)))objc_msgSend)(proxy, s, pid, ^(NSString *bundle, NSError *error) { found = bundle; dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
    if (![found isEqualToString:bundleID]) { @synchronized (self) { [_known removeObjectForKey:bundleID]; [_held removeObjectForKey:bundleID]; } return 0; }
    return pid;
}

- (int)holdApp:(NSString *)bundleID {
    int pid = [self knownPid:bundleID];
    if (pid <= 0) return 0;
    @synchronized (self) { if (_held[bundleID].intValue == pid) return pid; }
    id proxy = [self daemonProxy];
    SEL s = NSSelectorFromString(@"_XCT_requestBackgroundAssertionForPID:reply:");
    if (![proxy respondsToSelector:s]) return pid;
    __block BOOL granted = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    ((void (*)(id, SEL, int, void (^)(BOOL)))objc_msgSend)(proxy, s, pid, ^(BOOL ok) { granted = ok; dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    if (granted) { @synchronized (self) { _held[bundleID] = @(pid); } }
    NSLog(@"PokiBackground hold %@ pid %d assertion %@", bundleID, pid, granted ? @"granted" : @"not granted");
    return pid;
}

- (nullable id)rootSnapshot:(NSString *)bundleID code:(NSString **)code {
    NSDate *began = NSDate.date;
    int pid = [self holdApp:bundleID];
    if (pid <= 0) { if (code) *code = @"not_seen"; return nil; }
    NSString *given = nil;
    id root = [[PKInProcess shared] backgroundSnapshotForPID:pid code:&given];
    NSLog(@"PokiBackground snapshot %@ in %.2f s%@", bundleID, [NSDate.date timeIntervalSinceDate:began], root ? @"" : [@" failed: " stringByAppendingString:given ?: @"?"]);
    if (!root && code) *code = given ?: @"snapshot_failed";
    return root;
}

static void PKBGWalk(id snapshot, NSMutableArray<PKBackgroundElement *> *out) {
    PKBackgroundElement *e = [PKBackgroundElement new];
    e.index = (NSInteger)out.count;
    e.type = [[snapshot valueForKey:@"elementType"] unsignedIntegerValue];
    e.label = [snapshot valueForKey:@"label"] ?: @"";
    e.identifier = [snapshot valueForKey:@"identifier"] ?: @"";
    e.selected = [[snapshot valueForKey:@"isSelected"] boolValue];
    e.frame = [[snapshot valueForKey:@"frame"] CGRectValue];
    id value = [snapshot valueForKey:@"value"];
    e.value = [value isKindOfClass:NSString.class] ? value : ([value respondsToSelector:@selector(stringValue)] ? [value stringValue] : @"");
    e.actions = @[];
    e.snapshot = snapshot;
    [out addObject:e];
    for (id child in [snapshot valueForKey:@"children"] ?: @[]) PKBGWalk(child, out);
}

- (nullable NSArray<PKBackgroundElement *> *)elementsOf:(NSString *)bundleID code:(NSString **)code {
    id root = [self rootSnapshot:bundleID code:code];
    if (!root) return nil;
    NSMutableArray *out = [NSMutableArray array];
    PKBGWalk(root, out);
    // Swipe actions and More Info live on cells; one attribute read each, cells only.
    NSInteger cells = 0;
    for (PKBackgroundElement *e in out) {
        // One request to the app per cell: the first on-screen cells only, to keep a read quick.
        if (e.type != 75 /* cell */ || e.frame.size.height <= 0 || ++cells > 12) continue;
        NSMutableArray *names = [NSMutableArray array];
        for (NSDictionary *action in [self customActionsOf:e.snapshot]) {
            if ([action isKindOfClass:NSDictionary.class] && [action[@"CustomActionName"] isKindOfClass:NSString.class]) [names addObject:action[@"CustomActionName"]];
        }
        e.actions = names;
    }
    return out;
}

- (NSArray *)customActionsOf:(id)snapshot {
    id ax = [self axClient];
    SEL s = NSSelectorFromString(@"attributesForElement:attributes:error:");
    id element = [snapshot valueForKey:@"accessibilityElement"];
    if (!ax || !element || ![ax respondsToSelector:s]) return @[];
    NSError *error = nil;
    NSDictionary *values = ((id (*)(id, SEL, id, id, NSError **))objc_msgSend)(ax, s, element, @[@"XC_kAXXCAttributeCustomActions"], &error);
    id actions = [values isKindOfClass:NSDictionary.class] ? values[@"XC_kAXXCAttributeCustomActions"] : nil;
    return [actions isKindOfClass:NSArray.class] ? actions : @[];
}

- (nullable id)elementAt:(NSInteger)index in:(NSString *)bundleID {
    NSArray<PKBackgroundElement *> *all = [self elementsOf:bundleID code:NULL];
    return (index >= 0 && index < (NSInteger)all.count) ? all[index].snapshot : nil;
}

- (BOOL)perform:(NSInteger)action on:(id)snapshot value:(nullable id)value failure:(NSString **)failure {
    id ax = [self axClient];
    id element = [snapshot valueForKey:@"accessibilityElement"];
    SEL s = NSSelectorFromString(@"performAction:onElement:value:error:");
    Class actionClass = NSClassFromString(@"XCUIAccessibilityAction");
    if (!ax || !element || !actionClass || ![ax respondsToSelector:s]) { if (failure) *failure = @"unavailable"; return NO; }
    id actionObject = ((id (*)(id, SEL, NSInteger))objc_msgSend)([actionClass alloc], NSSelectorFromString(@"initWithAXAction:"), action);
    NSError *error = nil;
    BOOL ok = ((BOOL (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(ax, s, actionObject, element, value, &error);
    if (!ok && failure) *failure = error.localizedDescription ?: @"refused";
    return ok;
}

- (PKBackgroundOutcome *)activate:(NSInteger)index in:(NSString *)bundleID {
    id target = [self elementAt:index in:bundleID];
    if (!target) return [PKBackgroundOutcome failed:@"no_element"];
    NSString *failure = nil;
    // A refused activate means the control only answers a touch: no state changed, so the
    // foreground path can take over without any risk of a double action.
    if (![self perform:2010 on:target value:nil failure:&failure]) return [PKBackgroundOutcome front:failure];
    return [PKBackgroundOutcome ok];
}

- (void)layoutPass:(NSString *)bundleID {
    id root = [self rootSnapshot:bundleID code:NULL];
    id element = [root valueForKey:@"accessibilityElement"];
    id proxy = [self daemonProxy];
    SEL s = NSSelectorFromString(@"_XCT_fetchParameterizedAttributeForElement:attributes:parameter:reply:");
    if (!element || ![proxy respondsToSelector:s]) return;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSDictionary *audit = @{@"AXAuditClippingTest": @{@"AXAuditShouldRunTestOption": @YES}};
    ((void (*)(id, SEL, id, id, id, void (^)(id, NSError *)))objc_msgSend)(proxy, s, element, @95005, audit, ^(id value, NSError *error) { dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
}

- (PKBackgroundOutcome *)back:(NSString *)bundleID {
    NSArray<PKBackgroundElement *> *all = [self elementsOf:bundleID code:NULL];
    PKBackgroundElement *bar = nil;
    for (PKBackgroundElement *e in all) if (e.type == 21 /* XCUIElementTypeNavigationBar */) { bar = e; break; }
    if (!bar) return [PKBackgroundOutcome front:@"no_navigation_bar"];
    NSString *failure = nil;
    if (![self perform:2013 on:bar.snapshot value:nil failure:&failure]) return [PKBackgroundOutcome front:failure];
    // The pop is held until the navigation controller lays out; the audit's layout pass releases it.
    [self layoutPass:bundleID];
    return [PKBackgroundOutcome ok];
}

- (PKBackgroundOutcome *)customAction:(NSString *)name of:(NSInteger)index in:(NSString *)bundleID {
    id target = [self elementAt:index in:bundleID];
    if (!target) return [PKBackgroundOutcome failed:@"no_element"];
    NSArray *actions = [self customActionsOf:target];
    for (NSDictionary *action in actions) {
        if (![action isKindOfClass:NSDictionary.class] || ![action[@"CustomActionName"] isEqual:name]) continue;
        NSString *failure = nil;
        return [self perform:2021 on:target value:action failure:&failure] ? [PKBackgroundOutcome ok] : [PKBackgroundOutcome front:failure];
    }
    return [PKBackgroundOutcome front:@"no_such_action"];
}

- (PKBackgroundOutcome *)setValue:(NSString *)value of:(NSInteger)index in:(NSString *)bundleID {
    id target = [self elementAt:index in:bundleID];
    if (!target) return [PKBackgroundOutcome failed:@"no_element"];
    id ax = [self axClient];
    id element = [target valueForKey:@"accessibilityElement"];
    SEL s = NSSelectorFromString(@"setAttribute:value:element:outError:");
    if (!ax || !element || ![ax respondsToSelector:s]) return [PKBackgroundOutcome failed:@"unavailable"];
    NSError *error = nil;
    BOOL ok = ((BOOL (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(ax, s, @"XC_kAXXCAttributeValue", value, element, &error);
    return ok ? [PKBackgroundOutcome ok] : [PKBackgroundOutcome front:error.localizedDescription ?: @"refused"];
}

- (PKBackgroundOutcome *)scroll:(NSInteger)index direction:(NSInteger)direction in:(NSString *)bundleID {
    id target = [self elementAt:index in:bundleID];
    if (!target) return [PKBackgroundOutcome failed:@"no_element"];
    NSString *failure = nil;
    return [self perform:(direction >= 0 ? 2006 : 2007) on:target value:nil failure:&failure] ? [PKBackgroundOutcome ok] : [PKBackgroundOutcome front:failure];
}

- (PKBackgroundOutcome *)escape:(NSString *)bundleID {
    id root = [self rootSnapshot:bundleID code:NULL];
    if (!root) return [PKBackgroundOutcome failed:@"not_running"];
    dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
    Class rep = NSClassFromString(@"AXEventRepresentation");
    SEL make = NSSelectorFromString(@"keyRepresentationWithType:");
    if (!rep || ![rep respondsToSelector:make]) return [PKBackgroundOutcome failed:@"unavailable"];
    NSString *failure = nil;
    dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
    for (NSNumber *down in @[@YES, @NO]) {
        id event = ((id (*)(id, SEL, unsigned))objc_msgSend)(rep, make, down.boolValue ? 4500 : 4501);
        id info = [NSClassFromString(@"AXEventKeyInfoRepresentation") new];
        if (!event || !info) return [PKBackgroundOutcome failed:@"unavailable"];
        ((void (*)(id, SEL, id))objc_msgSend)(info, NSSelectorFromString(@"setUnmodifiedInput:"), @"UIKeyInputEscape");
        ((void (*)(id, SEL, id))objc_msgSend)(info, NSSelectorFromString(@"setModifiedInput:"), @"UIKeyInputEscape");
        ((void (*)(id, SEL, BOOL))objc_msgSend)(info, NSSelectorFromString(@"setKeyDown:"), down.boolValue);
        ((void (*)(id, SEL, id))objc_msgSend)(event, NSSelectorFromString(@"setKeyInfo:"), info);
        id data = PKBGSend(event, @"dataRepresentation");
        if (!data || ![self perform:2034 on:root value:data failure:&failure]) return [PKBackgroundOutcome front:failure ?: @"refused"];
        usleep(120000);
    }
    return [PKBackgroundOutcome ok];
}
@end

#endif
