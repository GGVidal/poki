import XCTest

extension SimFixtureTests {
    func testCHAMOIS() {
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW)
        guard let cls = NSClassFromString("SBSTestAutomationService") as? NSObject.Type else { say("CH | no class"); return }
        let svc = cls.init()
        let before = svc.perform(NSSelectorFromString("isChamoisWindowingUIEnabled"))
        say("CH | isChamoisWindowingUIEnabled before: \(String(describing: before))")
        typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
        let sel = NSSelectorFromString("setChamoisWindowingUIEnabled:")
        if let m = class_getInstanceMethod(cls, sel) { unsafeBitCast(method_getImplementation(m), to: F.self)(svc, sel, true); sleep(2) }
        typealias G = @convention(c) (AnyObject, Selector) -> Bool
        let gsel = NSSelectorFromString("isChamoisWindowingUIEnabled")
        let after = class_getInstanceMethod(cls, gsel).map { unsafeBitCast(method_getImplementation($0), to: G.self)(svc, gsel) }
        say("CH | isChamoisWindowingUIEnabled after set YES: \(String(describing: after))")
    }
}
