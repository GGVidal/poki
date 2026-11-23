import XCTest
import CryptoKit

// Background reach on a real app. Counts only: labels are read in memory for the allow/deny filter and never printed.
// Every action goes through testmanagerd (XCAXClient performAction / setAttribute). No touches, no AXElement press.
extension SimFixtureTests {
    static let allow = ["search", "搜索", "settings", "设置", "profile", "me", "我", "我的", "account", "账户", "menu", "菜单", "more", "更多", "filter", "筛选", "sort", "排序", "back", "返回", "close", "关闭", "cancel", "取消", "categories", "分类", "explore", "发现", "home", "首页", "notifications", "通知", "help", "帮助", "language"]
    static let deny = ["send", "发送", "pay", "支付", "付款", "buy", "购买", "下单", "order", "订单提交", "checkout", "结算", "purchase", "confirm", "确认", "submit", "提交", "request", "叫车", "book", "预订", "订票", "like", "赞", "喜欢", "follow", "关注", "subscribe", "订阅", "post", "发布", "发帖", "tweet", "repost", "转发", "share", "分享", "comment", "评论", "delete", "删除", "remove", "移除", "block", "拉黑", "report", "举报", "call", "呼叫", "拨打", "video call", "视频通话", "voice", "语音", "add to cart", "加入购物车", "favorite", "收藏", "save", "download", "下载", "install", "sign out", "log out", "退出登录", "transfer", "转账", "red packet", "红包", "scan", "扫一扫", "camera", "相机", "record", "live", "直播", "start", "开始", "play", "播放"]
    static let rowApps: Set<String> = ["com.atebits.Tweetie2", "com.xingin.discover", "com.burbn.instagram", "com.taobao.taobao4iphone", "com.360buy.jdmobile", "com.costco.costco", "com.meituan.imeituan", "com.marriott.iphoneprod", "com.amtrak.rider", "cn.12306.rails12306", "local.pokimcp.axfixture", "com.apple.MobileAddressBook"]
    func denied(_ e: XCUIElementSnapshot) -> Bool { let s = (e.label + " " + e.identifier).lowercased(); return s.trimmingCharacters(in: .whitespaces).isEmpty || Self.deny.contains { s.contains($0) } }
    func allowed(_ e: XCUIElementSnapshot) -> Bool { let s = e.label.lowercased(); return !denied(e) && Self.allow.contains { s == $0 || s.hasPrefix($0 + " ") || s.contains($0) && $0.unicodeScalars.first!.value > 0x2E00 } }
    func all(_ s: XCUIElementSnapshot?) -> [XCUIElementSnapshot] { var o: [XCUIElementSnapshot] = []; func w(_ e: XCUIElementSnapshot) { o.append(e); e.children.forEach(w) }; if let s { w(s) }; return o }
    func shape(_ app: XCUIApplication) -> String {
        let els = all(try? app.snapshot())
        let sig = els.map { "\($0.elementType.rawValue)\($0.isSelected ? "s" : "")" }.joined(separator: ",")
        return "\(els.count)-" + SHA256.hash(data: Data(sig.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
    func unexpected(_ app: XCUIApplication) -> Bool {
        let els = all(try? app.snapshot())
        return els.contains { $0.elementType == .alert || $0.elementType == .sheet } || els.contains { e in e.elementType == .staticText && ["支付", "pay", "login", "log in", "登录", "sign in"].contains { k in e.label.lowercased().contains(k) } }
    }
    func testREALAPP() {
        let env = ProcessInfo.processInfo.environment
        let bid = env["PROBE_BUNDLE"] ?? "local.pokimcp.axfixture"
        let frontBid = env["PROBE_FRONT"] ?? "com.apple.Preferences"
        let front = XCUIApplication(bundleIdentifier: frontBid)
        let app = XCUIApplication(bundleIdentifier: bid)
        background = true
        let t0 = Date(); var actions = 0
        func budget() -> Bool { actions < 20 && Date().timeIntervalSince(t0) < 180 }
        func frontOK() -> Bool { front.state == .runningForeground }
        let wasRunning = app.state.rawValue >= 2
        if !wasRunning && env["PROBE_LAUNCH_IN_TEST"] == "1" { app.launch(); sleep(3); front.activate(); _ = front.wait(for: .runningForeground, timeout: 10) }
        let pid = (app.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        let granted = pid > 0 ? (PBHelper.requestBackgroundAssertion(forPID: pid)?.intValue ?? -1) : -1
        var tree: XCUIElementSnapshot? = nil
        for _ in 0..<20 { tree = try? app.snapshot(); if all(tree).count > 5 { break }; sleep(1) }
        let els = all(tree)
        func n(_ t: XCUIElement.ElementType) -> Int { els.filter { $0.elementType == t }.count }
        let tabBar = els.first { $0.elementType == .tabBar }
        let tabs = all(tabBar).filter { $0.elementType == .button }
        say("REAL | app #\(env["PROBE_INDEX"] ?? "?") | running before \(wasRunning) | state \(app.state.rawValue) | assertion \(granted) | front ok \(frontOK())")
        say("REAL | counts | total \(els.count) | buttons \(n(.button)) cells \(n(.cell)) switches \(n(.switch)) textFields \(n(.textField) + n(.searchField)) links \(n(.link)) images \(n(.image)) staticTexts \(n(.staticText)) webViews \(n(.webView)) navBars \(n(.navigationBar)) tabBars \(n(.tabBar)) tabItems \(tabs.count) segmented \(n(.segmentedControl)) scrollViews \(n(.scrollView) + n(.collectionView) + n(.table))")
        guard els.count > 5 else { say("REAL | stopped: no tree"); return }
        var rec: [String: (Int, Int, Int)] = [:]
        func bump(_ k: String, _ changed: Bool, _ returned: Bool?) { var r = rec[k] ?? (0, 0, 0); r.0 += 1; if changed { r.1 += 1 }; if returned == true { r.2 += 1 }; rec[k] = r }
        func act(_ e: XCUIElementSnapshot, _ id: Int) -> Bool { actions += 1; var err: NSString?; let ok = PBHelper.pressSnapshot(e, action: id, value: nil, error: &err); usleep(1_200_000); return ok }
        func kick() { if let a = try? app.snapshot() { _ = PBHelper.daemonParamAttribute(95005, onSnapshot: a, parameter: ["AXAuditClippingTest": ["AXAuditShouldRunTestOption": true]] as NSDictionary) }; usleep(800_000) }
        func goBack(_ base: String) -> Bool {
            if shape(app) == base { return true }
            if let bar = all(try? app.snapshot()).first(where: { $0.elementType == .navigationBar }) { _ = act(bar, 2013); kick(); if shape(app) == base { return true } }
            if let c = all(try? app.snapshot()).first(where: { e in e.elementType == .button && ["close", "cancel", "关闭", "取消", "back", "返回"].contains { k in e.label.lowercased().contains(k) } }) { _ = act(c, 2010); kick() }
            return shape(app) == base
        }
        var stopped = ""
        func check() -> Bool { if !frontOK() { stopped = "front app changed" }; if stopped.isEmpty && unexpected(app) { stopped = "unexpected screen" }; return stopped.isEmpty }
        // 1 scroll
        if budget(), let sv = els.first(where: { [.scrollView, .collectionView, .table].contains($0.elementType) }) { let b = shape(app); _ = act(sv, 2006); let c = shape(app) != b; _ = act(sv, 2007); bump("scroll", c, shape(app) == b) }
        // 2 tabs
        if check(), tabs.count >= 2, let orig = tabs.first(where: { $0.isSelected }) {
            let base = shape(app)
            for i in tabs.indices where !tabs[i].isSelected && budget() && check() {
                let cur = all(all(try? app.snapshot()).first(where: { $0.elementType == .tabBar })).filter { $0.elementType == .button }; guard i < cur.count else { break }
                _ = act(cur[i], 2010); kick()
                let now = all(all(try? app.snapshot()).first(where: { $0.elementType == .tabBar })).filter { $0.elementType == .button }
                let moved = i < now.count && now[i].isSelected
                bump("tabs", moved, nil)
            }
            let curT = all(all(try? app.snapshot()).first(where: { $0.elementType == .tabBar })).filter { $0.elementType == .button }; if !curT.isEmpty, let oi = tabs.firstIndex(where: { $0.identifier == orig.identifier && $0.label == orig.label }), oi < curT.count { _ = act(curT[oi], 2010); kick(); rec["tabs"]?.2 = shape(app) == base ? 1 : 0 }
        }
        // 3 safe buttons
        if check() {
            let base = shape(app)
            let cands = all(try? app.snapshot()).filter { $0.elementType == .button && allowed($0) && $0.isEnabled && !(tabBar?.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) ?? false) }.prefix(4)
            for b in cands where budget() && check() {
                guard let cur = all(try? app.snapshot()).first(where: { $0.elementType == .button && $0.label == b.label && $0.frame == b.frame }) else { continue }
                _ = act(cur, 2010); kick(); let c = shape(app) != base; let ok = c ? goBack(base) : true; bump("buttons", c, ok); if !ok { stopped = "could not return"; break }
            }
        }
        // 4 content rows
        if check(), Self.rowApps.contains(bid) {
            let base = shape(app)
            let cells = all(try? app.snapshot()).filter { $0.elementType == .cell && !denied($0) }.prefix(2)
            for c in cells where budget() && check() {
                guard let cur = all(try? app.snapshot()).first(where: { $0.elementType == .cell && $0.frame == c.frame }) else { continue }
                _ = act(cur, 2010); kick(); let ch = shape(app) != base; let ok = ch ? goBack(base) : true; bump("rows", ch, ok); if !ok { stopped = "could not return"; break }
            }
        }
        // 5 segmented
        if check(), budget(), let seg = all(try? app.snapshot()).first(where: { $0.elementType == .segmentedControl }) {
            let segs = seg.children.filter { $0.elementType == .button && !denied($0) }
            if let orig = segs.first(where: { $0.isSelected }), let other = segs.first(where: { !$0.isSelected }) { let base = shape(app); _ = act(other, 2010); kick(); let c = shape(app) != base; if let o2 = all(try? app.snapshot()).first(where: { $0.frame == orig.frame && $0.elementType == .button }) { _ = act(o2, 2010); kick() }; bump("segmented", c, shape(app) == base) }
        }
        // 6 search field
        if check(), budget(), let sf = all(try? app.snapshot()).first(where: { $0.elementType == .searchField }) {
            var err: NSString?; actions += 1
            let ok = PBHelper.setAttribute("XC_kAXXCAttributeValue", value: "test", onSnapshot: sf, error: &err); usleep(800_000)
            let read = (all(try? app.snapshot()).first(where: { $0.elementType == .searchField })?.value as? String) == "test"
            if let sf2 = all(try? app.snapshot()).first(where: { $0.elementType == .searchField }) { _ = PBHelper.setAttribute("XC_kAXXCAttributeValue", value: "", onSnapshot: sf2, error: &err) }
            bump("search", ok && read, true)
        }
        let line = ["scroll", "tabs", "buttons", "rows", "segmented", "search"].map { k in rec[k].map { "\(k) \($0.0)/\($0.1)/\($0.2)" } ?? "\(k) -" }.joined(separator: " | ")
        say("REAL | results attempted/changed/returned | \(line) | switches counted \(n(.switch)) | actions \(actions) | \(stopped.isEmpty ? "completed" : "stopped: \(stopped)") | front ok \(frontOK()) | app state \(app.state.rawValue)")
    }
}
