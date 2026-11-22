import XCTest
@testable import Poki

/// What's New shows once after an update, stays dismissed on later launches of the same version,
/// reappears on a newer version, and never shows on a fresh install.
@MainActor
final class WhatsNewDecisionTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private let suite = "WhatsNewDecisionTests"

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhatsNewDecisionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func launch(version: String) {
        FirstRun.decide(defaults: defaults, sessionsFolder: folder)
        WhatsNew.decide(currentVersion: version, defaults: defaults, sessionsFolder: folder)
    }

    func testFreshInstallSkipsWhatsNewEvenAfterFinishingFirstRun() {
        launch(version: "0.5.0")
        XCTAssertFalse(
            WhatsNew.shouldPresent(currentVersion: "0.5.0", defaults: defaults),
            "A fresh install must not show What's New"
        )

        // Finishing the welcome guide and reopening the same version still must not show What's New.
        FirstRun.finish(defaults: defaults)
        launch(version: "0.5.0")
        XCTAssertFalse(
            WhatsNew.shouldPresent(currentVersion: "0.5.0", defaults: defaults),
            "Reopening the same version after a fresh install must not show What's New"
        )
    }

    func testUpgradeShowsOnceThenStaysDismissedUntilNextVersion() throws {
        // Seed an earlier version's trace (an existing user upgrading to 0.5.0).
        try Data("{}".utf8).write(to: folder.appendingPathComponent("old-1.json"))
        defaults.set(Data([1]), forKey: "setup")

        launch(version: "0.5.0")
        XCTAssertTrue(
            WhatsNew.shouldPresent(currentVersion: "0.5.0", defaults: defaults),
            "First launch after upgrading from an earlier version must show What's New"
        )

        // Closing the app without dismissing keeps it due on the next launch.
        launch(version: "0.5.0")
        XCTAssertTrue(
            WhatsNew.shouldPresent(currentVersion: "0.5.0", defaults: defaults),
            "What's New remains due until the user dismisses it"
        )

        // Once dismissed, subsequent launches of the same version never show it again.
        WhatsNew.markSeen(version: "0.5.0", defaults: defaults)
        launch(version: "0.5.0")
        XCTAssertFalse(
            WhatsNew.shouldPresent(currentVersion: "0.5.0", defaults: defaults),
            "Dismissed What's New must not appear again on the same version"
        )

        // Upgrading to a newer release shows What's New once again.
        launch(version: "0.5.1")
        XCTAssertTrue(
            WhatsNew.shouldPresent(currentVersion: "0.5.1", defaults: defaults),
            "Upgrading to a newer version must show What's New again"
        )
        WhatsNew.markSeen(version: "0.5.1", defaults: defaults)
        launch(version: "0.5.1")
        XCTAssertFalse(
            WhatsNew.shouldPresent(currentVersion: "0.5.1", defaults: defaults),
            "Dismissed newer What's New must not reappear"
        )
    }

    func testCatalogProvidesChineseAndEnglishCopyFromSingleRelease() {
        let release = WhatsNewCatalog.current
        XCTAssertEqual(release.version, "0.5.0")
        XCTAssertFalse(release.items.isEmpty)
        for item in release.items {
            XCTAssertFalse(item.title.resolved(for: "en").isEmpty)
            XCTAssertFalse(item.summary.resolved(for: "en").isEmpty)
            XCTAssertFalse(item.title.resolved(for: "zh-Hans").isEmpty)
            XCTAssertFalse(item.summary.resolved(for: "zh-Hans").isEmpty)
            XCTAssertFalse(item.title.resolved(for: "zh-Hant").isEmpty)
            XCTAssertFalse(item.summary.resolved(for: "zh-Hant").isEmpty)
            XCTAssertNotEqual(item.title.resolved(for: "en"), item.title.resolved(for: "zh-Hans"))
        }
    }
}
