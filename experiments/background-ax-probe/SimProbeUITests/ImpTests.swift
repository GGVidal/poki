import XCTest
import ObjectiveC

extension SimFixtureTests {
    func testIMP_press() {
        dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW)
        for (cls, sel) in [("AXElement", "press"), ("AXElement", "pressWithFallback"), ("AXElement", "simulatePress"), ("AXElement", "performAction:withValue:"), ("AXElement", "simulateTapWithFingerIndex:")] {
            guard let c = NSClassFromString(cls), let m = class_getInstanceMethod(c, NSSelectorFromString(sel)) else { say("IMP | \(cls) \(sel) | none"); continue }
            let imp = unsafeBitCast(method_getImplementation(m), to: UInt.self)
            var info = Dl_info(); dladdr(UnsafeRawPointer(bitPattern: imp), &info)
            let base = UInt(bitPattern: info.dli_fbase)
            say("IMP | \(cls) \(sel) | imp 0x\(String(imp, radix: 16)) base 0x\(String(base, radix: 16)) off 0x\(String(imp - base, radix: 16)) img \(String(cString: info.dli_fname).split(separator: "/").last ?? "")")
        }
    }
}
