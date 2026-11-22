#import "PBHelper.h"
#import <XCTest/XCTest.h>
#import <objc/message.h>

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
    id ax = [self ax];
    Class elCls = NSClassFromString(@"XCAccessibilityElement");
    SEL e = NSSelectorFromString(@"elementWithProcessIdentifier:");
    if (!ax || ![elCls respondsToSelector:e]) { if (status) *status = @"api unavailable"; return nil; }
    id element = ((id (*)(id, SEL, int))objc_msgSend)(elCls, e, pid);
    SEL s = NSSelectorFromString(@"requestSnapshotForElement:attributes:parameters:error:");
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    SEL d = NSSelectorFromString(@"defaultParameters");
    if ([ax respondsToSelector:d]) { id def = ((id (*)(id, SEL))objc_msgSend)(ax, d); if ([def isKindOfClass:NSDictionary.class]) [params addEntriesFromDictionary:def]; }
    params[@"maxDepth"] = @40; params[@"maxChildren"] = @400; params[@"maxArrayCount"] = @400; params[@"traverseFromParentsToChildren"] = @YES;
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

+ (BOOL)pressSnapshot:(id)snapshot action:(NSInteger)action error:(NSString **)error {
    id ax = [self ax];
    id element = nil;
    @try { element = [snapshot valueForKey:@"accessibilityElement"]; } @catch (__unused NSException *x) {}
    SEL s = NSSelectorFromString(@"performAction:onElement:value:error:");
    if (!element || ![ax respondsToSelector:s]) { if (error) *error = @"no element or selector"; return NO; }
    NSError *err = nil; BOOL ok = NO;
    @try { ok = ((BOOL (*)(id, SEL, NSInteger, id, id, NSError **))objc_msgSend)(ax, s, action, element, nil, &err); }
    @catch (NSException *x) { if (error) *error = [NSString stringWithFormat:@"exception %@: %@", x.name, x.reason]; return NO; }
    if (error) *error = err ? err.description : @"none";
    return ok;
}
@end
