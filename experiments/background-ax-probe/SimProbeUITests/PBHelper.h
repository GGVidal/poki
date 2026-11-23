#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Private XCTest calls, made from Objective-C so ARC and error out-parameters follow the
/// real method conventions (same approach as Poki's InProcess.m).
@interface PBHelper : NSObject
+ (nullable NSNumber *)requestBackgroundAssertionForPID:(int)pid;
+ (nullable id)snapshotForPID:(int)pid timeout:(NSTimeInterval)seconds status:(NSString * _Nullable * _Nullable)status;
+ (nullable id)snapshotForPID:(int)pid depth:(NSInteger)depth timeout:(NSTimeInterval)seconds status:(NSString * _Nullable * _Nullable)status;
+ (nullable id)snapshotOnCallerForPID:(int)pid status:(NSString * _Nullable * _Nullable)status;
+ (BOOL)setAttribute:(NSString *)name value:(id)value onSnapshot:(id)snapshot error:(NSString * _Nullable * _Nullable)error;
+ (NSString *)axRuntimeConstants;
+ (NSString *)describeAction:(NSInteger)action;
+ (NSString *)axElementRoute:(NSString *)route onSnapshot:(id)snapshot;
+ (NSString *)handTypeNames;
+ (NSString *)postTapAt:(CGPoint)p contextId:(unsigned)ctx pid:(int)pid displayId:(unsigned)display down:(int)down up:(int)up;
+ (unsigned)contextIdOfSnapshot:(id)snapshot;
+ (nullable id)keyEvent:(NSString *)input down:(BOOL)down asData:(BOOL)asData;
+ (nullable id)keyEvent:(NSString *)input down:(BOOL)down modifierKey:(NSString *)key modifierValue:(NSUInteger)value;
+ (NSString *)directAction:(NSInteger)action value:(nullable id)value onSnapshot:(id)snapshot;
+ (BOOL)pressSnapshot:(id)snapshot action:(NSInteger)action value:(nullable id)value error:(NSString * _Nullable * _Nullable)error;
+ (nullable id)paramAttribute:(NSInteger)attr onSnapshot:(id)snap parameter:(nullable id)param error:(NSError * _Nullable * _Nullable)err;
+ (NSString *)rawParamAttribute:(NSInteger)attr onSnapshot:(id)snap parameter:(nullable id)param;
+ (NSString *)setAXTimeout:(double)t;
+ (nullable id)axRef:(id)snap;
+ (nullable id)axCopy:(id)ref attr:(NSInteger)attr err:(int *)err;
+ (int)axPerform:(id)ref action:(NSInteger)action;
+ (int)axSet:(id)ref attr:(NSInteger)attr value:(id)value;
+ (NSString *)axLabel:(id)ref;
+ (nullable id)daemonAttributes:(NSArray<NSString *> *)names onSnapshot:(id)snap error:(NSString * _Nullable * _Nullable)error;
+ (int)axPerformValue:(id)ref action:(NSInteger)action value:(nullable id)value;
+ (nullable id)axAppElement:(int)pid;
+ (NSString *)fbsOpen:(NSString *)bundleID optionKeys:(NSArray<NSString *> *)keys;
+ (NSString *)rawAttribute:(NSInteger)attr onSnapshot:(id)snap;
+ (NSString *)daemonParamAttribute:(NSInteger)attr onSnapshot:(id)snap parameter:(nullable id)param;
+ (nullable id)paramAttributeString:(NSString *)attr onSnapshot:(id)snap parameter:(nullable id)param error:(NSError * _Nullable * _Nullable)err;
+ (BOOL)pressSnapshot:(id)snapshot action:(NSInteger)action error:(NSString * _Nullable * _Nullable)error;
+ (NSString *)setFullKeyboardAccess:(BOOL)on;
+ (NSString *)daemonActivate:(NSString *)bundleID timeout:(NSTimeInterval)t;
+ (NSString *)synthTapAt:(CGPoint)p timeout:(NSTimeInterval)t;
+ (NSString *)setReduceMotion:(BOOL)on;
+ (int)pidAtPoint:(CGPoint)p;
+ (nullable id)keyEventUsagePage:(NSUInteger)page usage:(NSUInteger)usage input:(NSString *)input down:(BOOL)down;
@end
NS_ASSUME_NONNULL_END
