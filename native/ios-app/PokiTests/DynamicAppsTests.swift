import UIKit
import XCTest
@testable import Poki

/// Apps Poki does not list by name still show with their name and icon once the phone's app list has
/// them: the list's names give the bundle id, the id gives the iPhone's icon or the App Store's.
@MainActor
final class DynamicAppsTests: XCTestCase {
    private let strava = DynamicApps.Entry(id: "com.strava.stravaride", name: "Strava", user: true)
    private let chagee = DynamicApps.Entry(id: "com.chagee.application.cn", name: "霸王茶姬", user: true)

    private func reset() {
        DynamicApps.set([])
        try? FileManager.default.removeItem(at: InstalledApps.cacheFile)
    }
    override func setUp() async throws { reset() }
    override func tearDown() async throws { reset() }

    private func capsules(_ plain: String) -> [String] {
        CapsuleText.segments(plain).compactMap { if case .app(let app, _) = $0 { app.id } else { nil } }
    }

    func testAnInstalledAppsNameGivesItsBundleIDAndBack() {
        XCTAssertNil(AppIconStore.bundleID("Strava"))
        DynamicApps.set([strava, chagee])
        XCTAssertEqual(AppIconStore.bundleID("Strava"), "com.strava.stravaride")
        XCTAssertEqual(AppIconStore.bundleID("strava"), "com.strava.stravaride")
        XCTAssertEqual(AppIconStore.bundleID("霸王茶姬"), "com.chagee.application.cn")
        XCTAssertEqual(AppIconStore.name("com.strava.stravaride"), "Strava")
        XCTAssertEqual(AppName.display("com.strava.stravaride"), "Strava", "an installed app's id reads as its name")
        XCTAssertEqual(AppIconStore.bundleID("淘宝"), "com.taobao.taobao4iphone", "KnownApps still first")
    }

    func testANameTwoAppsShareFindsNeither() {
        DynamicApps.set([strava, .init(id: "com.example.strava", name: "Strava", user: true)])
        XCTAssertNil(DynamicApps.id(forName: "Strava"))
        XCTAssertEqual(DynamicApps.name(forID: "com.example.strava"), "Strava")
    }

    func testTheIconComesOnceTheListArrives() {
        let red = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        let store = AppIconStore(installed: { id, _ in id == "com.strava.stravaride" ? red : nil })
        XCTAssertNil(store.icon("Strava"), "no id for the name yet")
        DynamicApps.set([strava])
        store.directoryChanged()
        XCTAssertTrue(store.icon("Strava") === red)
    }

    func testInstalledUserAppsBecomeCapsulesCarefully() {
        DynamicApps.set([strava, chagee, .init(id: "com.apple.PrintCenter", name: "Print Center", user: false)])
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"])
        XCTAssertEqual(capsules("open strava"), [], "an unlisted Latin name counts only as written")
        XCTAssertEqual(capsules("打开霸王茶姬点一杯"), ["com.chagee.application.cn"])
        XCTAssertEqual(capsules("我想喝霸王茶姬"), [], "an unlisted Chinese name only where an app goes")
        XCTAssertEqual(capsules("Print Center is slow"), [], "system apps are not capsules")
        XCTAssertEqual(capsules("打开淘宝"), ["com.taobao.taobao4iphone"], "KnownApps capsules stay")
        DynamicApps.set([])
        XCTAssertEqual(capsules("Open Strava and log my run"), [], "the table follows the list")
    }

    /// A name two installed apps share makes no capsule, whichever the phone lists first; the app
    /// beside them with a name of its own still does.
    func testANameTwoAppsShareMakesNoCapsuleInEitherOrder() {
        let other = DynamicApps.Entry(id: "com.example.strava", name: "Strava", user: true)
        for list in [[strava, other, chagee], [other, strava, chagee], [chagee, other, strava]] {
            DynamicApps.set(list)
            XCTAssertEqual(capsules("Open Strava and log my run"), [], "\(list.map(\.id))")
            XCTAssertEqual(capsules("打开霸王茶姬点一杯"), ["com.chagee.application.cn"], "\(list.map(\.id))")
        }
        // A system app with the same name takes the name away too.
        DynamicApps.set([strava, .init(id: "com.apple.strava", name: "Strava", user: false)])
        XCTAssertEqual(capsules("Open Strava and log my run"), [])
        DynamicApps.set([strava])
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"])
    }

    /// The signer's answer, as it comes over the bridge, is decoded, reaches the names and capsules, and
    /// is kept in the file a later launch reads. A wrong key for the name or the type, or a list that is
    /// never published, fails here.
    func testTheSignersAnswerReachesTheNamesTheCapsulesAndTheFile() async throws {
        let answer = Data(#"{"v":{"apps":[{"id":"com.strava.stravaride","name":"Strava","bundle_name":"StravaRide","type":"User"},{"id":"com.apple.PrintCenter","bundle_name":"Print Center","type":"System"}]}}"#.utf8)
        var asked: [String: Any] = [:]
        let apps = InstalledApps(publishes: true)
        apps.phone = { ["device_address": "10.7.0.1"] }
        apps.call = { request in asked = request; return answer }
        let inventory = await apps.list()
        XCTAssertEqual(asked["op"] as? String, "apps")
        XCTAssertEqual(asked["device_address"] as? String, "10.7.0.1")
        XCTAssertEqual(inventory?.apps, [.init(id: "com.strava.stravaride", name: "Strava", bundleName: "StravaRide", type: "User"),
                                         .init(id: "com.apple.PrintCenter", name: nil, bundleName: "Print Center", type: "System")])
        XCTAssertEqual(AppIconStore.bundleID("Strava"), "com.strava.stravaride")
        XCTAssertEqual(AppName.display("com.apple.PrintCenter"), "Print Center", "the bundle's name where there is no display name")
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"], "a User app is a capsule")
        XCTAssertEqual(capsules("Print Center is slow"), [], "a System app is not")

        // The file holds the same list, stays out of backups, and a later launch publishes from it.
        let saved = try JSONDecoder().decode([InstalledApps.App].self, from: Data(contentsOf: InstalledApps.cacheFile))
        XCTAssertEqual(saved, inventory?.apps)
        XCTAssertEqual(try InstalledApps.cacheFile.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        DynamicApps.set([])
        XCTAssertNil(AppIconStore.bundleID("Strava"))
        _ = InstalledApps(publishes: true)
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"])

        // A file older than 30 days is removed unread.
        DynamicApps.set([])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-InstalledApps.cacheMaxAge - 60)], ofItemAtPath: InstalledApps.cacheFile.path)
        _ = InstalledApps(publishes: true)
        XCTAssertNil(AppIconStore.bundleID("Strava"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: InstalledApps.cacheFile.path))
    }

    /// A finder that is not the shared one keeps the list to itself.
    func testOnlyThePublishingFinderFeedsTheIndex() async throws {
        let apps = InstalledApps()
        apps.phone = { [:] }
        apps.call = { _ in try AppLaunchPromptTests.signerAnswer([.init(id: "com.strava.stravaride", name: "Strava", bundleName: nil, type: "User")]) }
        _ = await apps.list()
        XCTAssertNil(DynamicApps.id(forName: "Strava"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: InstalledApps.cacheFile.path))
    }
}
