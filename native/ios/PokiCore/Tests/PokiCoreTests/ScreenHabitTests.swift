import Foundation
import XCTest
@testable import PokiCore

/// The usual music app is worked out from which app was in front and when. These pin the rules the
/// owner was promised: real uses, not rows; several days; recent; a clear lead over other music apps;
/// and nothing from Poki's own launches or from before the owner said stop.
final class ScreenHabitTests: XCTestCase {
    static let netease = "com.netease.cloudmusic"
    static let appleMusic = "com.apple.Music"
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2026-11-18 20:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_795_032_000)

    /// One use of `app`: a few reads a minute apart, `daysAgo` days before `now` at `hour` UTC.
    static func use(_ app: String, daysAgo: Int, hour: Int, reads: Int = 3) -> [ScreenHabitRawObservation] {
        let day = utc.startOfDay(for: now).addingTimeInterval(Double(-daysAgo) * 86_400)
        let start = day.addingTimeInterval(Double(hour) * 3600)
        return (0..<reads).map { ScreenHabitRawObservation(at: start.addingTimeInterval(Double($0) * 60), bundleID: app) }
    }

    static func evaluate(_ rows: [ScreenHabitRawObservation], spans: [AgentAppSpan] = [], watermark: Date? = nil,
                         keeps: @escaping (String) -> Bool = { _ in true }) -> InferredMusicAppHabit? {
        MusicHabitEvaluator.evaluate(observations: rows, agentSpans: spans, watermarkAt: watermark, keepsApp: keeps, now: now, calendar: utc)
    }

    func testFiveUsesOverThreeDaysMakeTheHabit() throws {
        let rows = Self.use(Self.netease, daysAgo: 2, hour: 9) + Self.use(Self.netease, daysAgo: 2, hour: 18)
            + Self.use(Self.netease, daysAgo: 1, hour: 9) + Self.use(Self.netease, daysAgo: 1, hour: 18) + Self.use(Self.netease, daysAgo: 0, hour: 9)
        let habit = try XCTUnwrap(Self.evaluate(rows))
        XCTAssert(habit.bundleID == Self.netease)
        XCTAssert(habit.activeSessionCount == 5)
        XCTAssert(habit.distinctDayCount == 3)
        XCTAssert(habit.weightedShare == 1)
    }

    func testManyRowsOfOneUseCountOnce() {
        // A hundred reads of the same page each day are three uses, not three hundred.
        let rows = (0..<3).flatMap { Self.use(Self.netease, daysAgo: $0, hour: 10, reads: 100) }
        XCTAssertNil(Self.evaluate(rows))
    }

    func testTenOpeningsInADayCountTwice() {
        // Ten uses an hour apart on two days: at most two a day count, so four in all.
        let rows = (0..<2).flatMap { day in (0..<10).flatMap { Self.use(Self.netease, daysAgo: day, hour: 8 + $0) } }
        XCTAssertNil(Self.evaluate(rows))
    }

    func testFourUsesAreNotEnough() {
        let rows = Self.use(Self.netease, daysAgo: 2, hour: 9) + Self.use(Self.netease, daysAgo: 1, hour: 9)
            + Self.use(Self.netease, daysAgo: 1, hour: 18) + Self.use(Self.netease, daysAgo: 0, hour: 9)
        XCTAssertNil(Self.evaluate(rows))
    }

    func testFiveUsesOnTwoDaysAreNotEnough() {
        let rows = [9, 12, 15].flatMap { Self.use(Self.netease, daysAgo: 1, hour: $0) }
            + [9, 12].flatMap { Self.use(Self.netease, daysAgo: 0, hour: $0) }
        XCTAssertNil(Self.evaluate(rows))
    }

    func testUsesOlderThanTwoWeeksDoNotCount() {
        let rows = (15..<20).flatMap { Self.use(Self.netease, daysAgo: $0, hour: 9) + Self.use(Self.netease, daysAgo: $0, hour: 18) }
        XCTAssertNil(Self.evaluate(rows))
    }

    func testNoUseInTheLastWeekEndsTheHabit() {
        let rows = (8..<12).flatMap { Self.use(Self.netease, daysAgo: $0, hour: 9) + Self.use(Self.netease, daysAgo: $0, hour: 18) }
        XCTAssertNil(Self.evaluate(rows))
    }

    func testALeadOfSeventyPercentMakesTheHabit() throws {
        // NetEase twice a day for four days, Apple Music once a day on three: about 72%.
        let rows = (0..<4).flatMap { Self.use(Self.netease, daysAgo: $0, hour: 9) + Self.use(Self.netease, daysAgo: $0, hour: 18) }
            + (0..<3).flatMap { Self.use(Self.appleMusic, daysAgo: $0, hour: 13) }
        let habit = try XCTUnwrap(Self.evaluate(rows))
        XCTAssert(habit.bundleID == Self.netease)
        XCTAssert(habit.weightedShare > 0.7 && habit.weightedShare < 0.75)
    }

    func testALeadUnderSeventyPercentMakesNoHabit() {
        // Twice a day for three days against once a day on the same days: about 67%.
        let rows = (0..<3).flatMap { Self.use(Self.netease, daysAgo: $0, hour: 9) + Self.use(Self.netease, daysAgo: $0, hour: 18) }
            + (0..<3).flatMap { Self.use(Self.appleMusic, daysAgo: $0, hour: 13) }
        XCTAssertNil(Self.evaluate(rows))
    }

    func testPokisOwnLaunchesAreNotEvidence() {
        // Two uses by the owner, then Poki opened NetEase twenty times: still no habit.
        let owner = Self.use(Self.netease, daysAgo: 3, hour: 9) + Self.use(Self.netease, daysAgo: 2, hour: 9)
        var agent: [ScreenHabitRawObservation] = []
        var spans: [AgentAppSpan] = []
        for i in 0..<20 {
            let rows = Self.use(Self.netease, daysAgo: i % 3, hour: 6 + i / 3 * 2)
            agent += rows
            spans.append(AgentAppSpan(bundleID: Self.netease, startAt: rows[0].at.addingTimeInterval(-5), endAt: rows[rows.count - 1].at.addingTimeInterval(90)))
        }
        XCTAssertNil(Self.evaluate(owner + agent, spans: spans))
        // The same rows without the spans would have made one.
        XCTAssert(Self.evaluate(owner + agent)?.bundleID == Self.netease)
    }

    func testUsesBeforeTheOwnerSaidStopDoNotCount() {
        let rows = Self.use(Self.netease, daysAgo: 2, hour: 9) + Self.use(Self.netease, daysAgo: 2, hour: 18)
            + Self.use(Self.netease, daysAgo: 1, hour: 9) + Self.use(Self.netease, daysAgo: 1, hour: 18) + Self.use(Self.netease, daysAgo: 0, hour: 9)
        XCTAssertNil(Self.evaluate(rows, watermark: Self.now.addingTimeInterval(-60)))
        // Uses after it count again from zero.
        let watermark = Self.now.addingTimeInterval(-2.5 * 86_400)
        XCTAssert(Self.evaluate(rows, watermark: watermark)?.activeSessionCount == 5)
    }

    func testAnExcludedMusicAppStopsTheHabit() {
        // Apple Music is left out of Screen History, so NetEase's 100% says nothing.
        let rows = Self.use(Self.netease, daysAgo: 2, hour: 9) + Self.use(Self.netease, daysAgo: 2, hour: 18)
            + Self.use(Self.netease, daysAgo: 1, hour: 9) + Self.use(Self.netease, daysAgo: 1, hour: 18) + Self.use(Self.netease, daysAgo: 0, hour: 9)
        XCTAssertNil(Self.evaluate(rows, keeps: { $0 != Self.appleMusic }))
    }
}
