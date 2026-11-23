// Experimental (issue #656): operate an app that is not in front through Poki's own testmanagerd
// session, without bringing it forward. Called only from code compiled with POKI_EXPERIMENTS and
// gated by an off-by-default setting, so normal Poki builds never reach it.
#import <Foundation/Foundation.h>

#if POKI_EXPERIMENTS

NS_ASSUME_NONNULL_BEGIN

/// One element of a background app's tree, flattened in depth-first order.
@interface PKBackgroundElement : NSObject
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSUInteger type;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly) BOOL selected;
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly, copy) NSString *value;
/// Custom action names (read for cells only, where swipe actions live).
@property (nonatomic, readonly, copy) NSArray<NSString *> *actions;
@end

/// The result of one background step. `background` says whether the step ran with the app kept in
/// the background; `needsFront` says the control did not respond and the caller should fall back to
/// the normal foreground path.
@interface PKBackgroundOutcome : NSObject
@property (nonatomic, readonly) BOOL background;
@property (nonatomic, readonly) BOOL needsFront;
@property (nonatomic, readonly, copy, nullable) NSString *failure;
@end

@interface PKBackground : NSObject
+ (instancetype)shared;

/// Notes the pid of an app Poki saw in front; background steps need one (no app lookup by bundle
/// works outside a UI test).
- (void)remember:(NSString *)bundleID pid:(int)pid;
/// Keeps `bundleID` running in the background (testmanagerd assertion) and returns its pid, or 0.
- (int)holdApp:(NSString *)bundleID;
/// Reads the app's tree. Elements are numbered in depth-first order, the same order on every read.
- (nullable NSArray<PKBackgroundElement *> *)elementsOf:(NSString *)bundleID code:(NSString *_Nullable *_Nullable)code;
/// Activates an element (accessibility activate). Fails cleanly for controls that need a touch.
- (PKBackgroundOutcome *)activate:(NSInteger)index in:(NSString *)bundleID;
/// Goes back on the current navigation stack: escape on the navigation bar, then a layout pass.
- (PKBackgroundOutcome *)back:(NSString *)bundleID;
/// Runs a named accessibility custom action of an element (swipe actions, More Info).
- (PKBackgroundOutcome *)customAction:(NSString *)name of:(NSInteger)index in:(NSString *)bundleID;
/// Sets an element's value (text fields, search fields). Does not submit.
- (PKBackgroundOutcome *)setValue:(NSString *)value of:(NSInteger)index in:(NSString *)bundleID;
/// Scrolls an element by a page (direction 1 = down or forward, -1 = up or back).
- (PKBackgroundOutcome *)scroll:(NSInteger)index direction:(NSInteger)direction in:(NSString *)bundleID;
/// Lets a background app finish a held transition (a push or pop waits for a layout pass that a
/// background app never runs on its own).
- (void)layoutPass:(NSString *)bundleID;
/// Sends the Escape key to the app (cancels a UIKit alert or action sheet).
- (PKBackgroundOutcome *)escape:(NSString *)bundleID;
@end

NS_ASSUME_NONNULL_END

#endif
