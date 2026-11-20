#import <UIKit/UIKit.h>
#import "InProcess.h"
#import "RecoveredNative.h"

// The simulator ordinarily enumerates only its cover. Supply the two screens
// XCTest reported on the physical Duo in #472, including its unchanged default.
@interface XCUIScreen : NSObject
@property(nonatomic) CGRect bounds;
@property(nonatomic) long long displayID;
@property(nonatomic, strong) NSData *pixels;
@end

static NSArray<XCUIScreen *> *panels;
static long long capturedDisplayID;

@implementation XCUIScreen
+ (NSArray *)screens { return panels; }
+ (instancetype)mainScreen { return panels.firstObject; }
- (instancetype)screenshot { capturedDisplayID = self.displayID; return self; }
- (NSData *)PNGRepresentation { return self.pixels; }
@end

@interface ReadySession : SRNativeSession
@end
@implementation ReadySession
- (id)prepare:(NSError **)error { return self; }
- (uint64_t)generation { return 1; }
@end

@interface FoldFixture : PKInProcess
@property(nonatomic) PKDisplayGeometry currentGeometry;
@property(nonatomic) CGRect targetPane;
@end
@implementation FoldFixture
- (PKDisplayGeometry)sceneDisplayGeometry { return self.currentGeometry; }
// The foreground scene supplies known geometry; this check needs no AX or daemon session.
- (BOOL)isPokiSceneVisible { return YES; }
- (NSData *)daemonJPEGForScreen:(id)screen { return nil; }
- (id)sharedFront:(NSDictionary **)info ax:(id *)ax code:(NSString **)code {
    if (info) *info = @{@"pane": [NSValue valueWithCGRect:self.targetPane]};
    return nil;
}
@end

static XCUIScreen *panel(long long displayID, CGSize grid, CGSize picture, UIColor *color) {
    XCUIScreen *screen = [XCUIScreen new];
    screen.displayID = displayID;
    screen.bounds = (CGRect){CGPointZero, grid};
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:picture format:format];
    screen.pixels = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill];
        [context fillRect:(CGRect){CGPointZero, picture}];
    }];
    return screen;
}

// Both fixture rasters are solid, so a single decoded grayscale sample identifies their content.
static int graySample(CGImageRef image) {
    if (!image) return -1;
    uint8_t gray = 0;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(&gray, 1, 1, 8, 1, space, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(space);
    if (!context) return -1;
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image);
    CGContextRelease(context);
    return gray;
}

static BOOL checkShot(FoldFixture *runner, long long displayID, CGSize expected, int expectedGray, NSString *stage, BOOL split) {
    capturedDisplayID = 0;
    NSString *reason = nil;
    NSData *data = [runner screenshot:&reason refreshViewport:split];
    UIImage *picture = data ? [UIImage imageWithData:data] : nil;
    CGImageRef image = picture.CGImage;
    CGSize actual = image ? CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image)) : CGSizeZero;
    int gray = graySample(image);
    printf("%s: expected display %lld %.0fx%.0f gray %d, got display %lld %.0fx%.0f gray %d%s%s\n",
           stage.UTF8String, displayID, expected.width, expected.height, expectedGray, capturedDisplayID,
           actual.width, actual.height, gray, reason ? ": " : "", reason.UTF8String ?: "");
    return capturedDisplayID == displayID && CGSizeEqualToSize(actual, expected) &&
           gray >= 0 && abs(gray - expectedGray) <= 2;
}

int main(void) {
    @autoreleasepool {
        CGSize cover = CGSizeMake(1398, 2034), inner = CGSizeMake(2852, 2006);
        panels = @[panel(1, cover, cover, UIColor.blackColor),
                   panel(2, CGSizeMake(2007, 2853), inner, UIColor.whiteColor)];
        FoldFixture *runner = [FoldFixture new];
        [runner setValue:[ReadySession new] forKey:@"sessions"];
        PKDisplayGeometry geometry = {.bounds = CGRectMake(0, 0, 466, 678),
            .peer = CGRectNull, .nativeSize = cover, .toFixed = CGAffineTransformIdentity,
            .orientation = UIInterfaceOrientationPortrait, .routesDisplay = YES};
        runner.currentGeometry = geometry;
        if (!checkShot(runner, 1, cover, 0, @"cover", NO)) return 1;

        geometry.bounds = CGRectMake(0, 0, 951, 669);
        geometry.nativeSize = CGSizeMake(1878, 2670);
        geometry.toFixed = CGAffineTransformMake(0, -1, 1, 0, 0, 951);
        geometry.orientation = UIInterfaceOrientationLandscapeLeft;
        geometry.orientationRevision++;
        runner.currentGeometry = geometry;
        if (!checkShot(runner, 2, inner, 255, @"unfolded inner landscape", NO)) return 1;

        XCUIScreen *active = panels[1];
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        format.opaque = YES;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:inner format:format];
        active.pixels = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.whiteColor setFill];
            [context fillRect:(CGRect){CGPointZero, inner}];
            [UIColor.blackColor setFill];
            [context fillRect:CGRectMake(0, 0, 1407, inner.height)];
        }];
        geometry.bounds = CGRectMake(0, 0, 469, 669);
        geometry.nativeSize = CGSizeMake(2007, 1407);
        runner.currentGeometry = geometry;
        runner.targetPane = CGRectMake(482, 0, 469, 669);
        CGSize crop = CGSizeMake(1407, 2006);
        if (!checkShot(runner, 2, crop, 255, @"Poki left, target right", YES)) return 1;

        geometry.bounds.size.width = 389;
        geometry.nativeSize.height = 1167;
        runner.currentGeometry = geometry;
        runner.targetPane = CGRectMake(0, 0, 469, 669);
        return checkShot(runner, 2, crop, 0, @"Poki right, target left", YES) ? 0 : 1;
    }
}
