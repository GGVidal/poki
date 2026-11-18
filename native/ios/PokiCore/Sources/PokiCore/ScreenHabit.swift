import Foundation

/// Habits Poki learns from Screen History, computed on this iPhone from which app was in front and
/// when. No screen text or title goes in. Today there is one: the music app the owner uses most.

// MARK: Types

public enum HabitInferenceSource: String, Codable, Equatable, Sendable {
    case screenHistoryLocalStats = "screen_history_local_stats"
}

public struct InferredMusicAppHabit: Codable, Equatable, Sendable {
    public var bundleID: String
    public var source: HabitInferenceSource
    public var windowStart: Date
    public var windowEnd: Date
    public var activeSessionCount: Int
    public var distinctDayCount: Int
    public var lastObservedAt: Date
    public var weightedShare: Double
    public var computedAt: Date
    public var expiresAt: Date

    public init(
        bundleID: String,
        source: HabitInferenceSource = .screenHistoryLocalStats,
        windowStart: Date,
        windowEnd: Date,
        activeSessionCount: Int,
        distinctDayCount: Int,
        lastObservedAt: Date,
        weightedShare: Double,
        computedAt: Date,
        expiresAt: Date? = nil
    ) {
        self.bundleID = bundleID
        self.source = source
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.activeSessionCount = activeSessionCount
        self.distinctDayCount = distinctDayCount
        self.lastObservedAt = lastObservedAt
        self.weightedShare = weightedShare
        self.computedAt = computedAt
        self.expiresAt = expiresAt ?? lastObservedAt.addingTimeInterval(7 * 86_400)
    }
}

public struct ScreenHabitRawObservation: Equatable, Sendable {
    public var id: Int64
    public var at: Date
    public var bundleID: String
    public var isAgentInitiated: Bool

    public init(id: Int64 = 0, at: Date, bundleID: String, isAgentInitiated: Bool = false) {
        self.id = id
        self.at = at
        self.bundleID = bundleID
        self.isAgentInitiated = isAgentInitiated
    }
}

public struct AgentAppSpan: Codable, Equatable, Sendable {
    public var bundleID: String
    public var startAt: Date
    public var endAt: Date

    public init(bundleID: String, startAt: Date, endAt: Date) {
        self.bundleID = bundleID
        self.startAt = startAt
        self.endAt = endAt
    }
}

// MARK: Music App Catalog

public enum MusicAppCatalog {
    public static let allCanonicalIDs: [String] = [
        "com.apple.Music",
        "com.netease.cloudmusic",
        "com.tencent.QQMusic",
        "com.spotify.client",
        "com.kugou.kugou1002",
        "com.yeelion.kwplayer",
        "com.luna.music",
        "com.google.ios.youtubemusic",
        "com.apple.Classical",
    ]

    private static let aliasToCanonical: [String: String] = {
        var map: [String: String] = [:]
        for id in allCanonicalIDs {
            map[id.lowercased()] = id
        }
        map["com.netease.cloudmusic.ipad"] = "com.netease.cloudmusic"
        map["com.tencent.qqmusichd"] = "com.tencent.QQMusic"
        map["com.kugou.kugou"] = "com.kugou.kugou1002"
        map["cn.kuwo.player"] = "com.yeelion.kwplayer"
        return map
    }()

    public static func isValidBundleID(_ rawBundleID: String) -> Bool {
        rawBundleID.range(of: #"\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z"#, options: .regularExpression) != nil
    }

    public static func canonicalBundleID(for rawBundleID: String) -> String? {
        guard isValidBundleID(rawBundleID) else { return nil }
        return aliasToCanonical[rawBundleID.lowercased()]
    }

    public static func isMusicApp(_ rawBundleID: String) -> Bool {
        canonicalBundleID(for: rawBundleID) != nil
    }
}

// MARK: Evaluator

public enum MusicHabitEvaluator {
    public static let sessionMergeInterval: TimeInterval = 30 * 60
    public static let maxSessionsPerDay = 2
    public static let minActiveSessions = 5
    public static let minDistinctDays = 3
    public static let windowSeconds: TimeInterval = 14 * 86_400
    public static let recentRequiredSeconds: TimeInterval = 7 * 86_400
    public static let decayHalfLifeSeconds: TimeInterval = 7 * 86_400
    public static let requiredWeightedShare: Double = 0.70

    private struct OpenSession {
        var startAt: Date
        var endAt: Date
        var firstOtherAppAt: Date?
        var taintedByAgent: Bool
    }

    public struct Session: Equatable, Sendable {
        public var bundleID: String
        public var startAt: Date
        public var endAt: Date
    }

    /// Evaluates foreground bundle ID observations locally without inspecting any screen text or titles.
    public static func evaluate(
        observations: [ScreenHabitRawObservation],
        agentSpans: [AgentAppSpan] = [],
        watermarkAt: Date? = nil,
        keepsApp: (String) -> Bool = { _ in true },
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InferredMusicAppHabit? {
        // Survivorship guard: if any known music app is excluded or omitted by allowlist mode,
        // competing usage cannot be observed fairly, so do not infer a default preference.
        guard MusicAppCatalog.allCanonicalIDs.allSatisfy({ keepsApp($0) }) else {
            return nil
        }

        let windowFloor = now.addingTimeInterval(-windowSeconds)
        let prefilterFloor = windowFloor.addingTimeInterval(-sessionMergeInterval * 2)
        let upperBound = now.addingTimeInterval(1)

        let normalizedSpans: [(canonicalOrLower: String, startAt: Date, endAt: Date)] = agentSpans.compactMap { span in
            guard MusicAppCatalog.isValidBundleID(span.bundleID) else { return nil }
            let key = MusicAppCatalog.canonicalBundleID(for: span.bundleID) ?? span.bundleID.lowercased()
            return (key, span.startAt, max(span.startAt, span.endAt))
        }

        func isAgentTriggered(canonicalApp: String, at time: Date, flagged: Bool) -> Bool {
            if flagged { return true }
            for span in normalizedSpans where span.canonicalOrLower == canonicalApp {
                if time >= span.startAt && time <= span.endAt {
                    return true
                }
            }
            return false
        }

        let sanitized = observations.filter { item in
            guard MusicAppCatalog.isValidBundleID(item.bundleID) else { return false }
            guard item.at >= prefilterFloor && item.at <= upperBound else { return false }
            if let watermarkAt, item.at <= watermarkAt { return false }
            guard keepsApp(item.bundleID) else { return false }
            if let canonical = MusicAppCatalog.canonicalBundleID(for: item.bundleID), !keepsApp(canonical) {
                return false
            }
            return true
        }.sorted { lhs, rhs in
            if lhs.at == rhs.at { return lhs.id < rhs.id }
            return lhs.at < rhs.at
        }

        guard !sanitized.isEmpty else { return nil }

        var openByApp: [String: OpenSession] = [:]
        var completedByApp: [String: [OpenSession]] = [:]

        for item in sanitized {
            let clampedAt = min(item.at, now)
            let canonicalMusic = MusicAppCatalog.canonicalBundleID(for: item.bundleID)
            let currentIdentity = canonicalMusic ?? item.bundleID.lowercased()

            for existingApp in Array(openByApp.keys) where existingApp != currentIdentity {
                if openByApp[existingApp]?.firstOtherAppAt == nil {
                    openByApp[existingApp]?.firstOtherAppAt = clampedAt
                }
            }

            guard let musicApp = canonicalMusic else { continue }
            let agentFlag = isAgentTriggered(canonicalApp: musicApp, at: clampedAt, flagged: item.isAgentInitiated)

            if var active = openByApp[musicApp] {
                let directGap = clampedAt.timeIntervalSince(active.endAt)
                let mergedBySwitch: Bool = {
                    guard let switchedAt = active.firstOtherAppAt else { return false }
                    return switchedAt.timeIntervalSince(active.endAt) <= sessionMergeInterval
                        && clampedAt.timeIntervalSince(switchedAt) <= sessionMergeInterval
                }()

                if directGap <= sessionMergeInterval || mergedBySwitch {
                    active.endAt = max(active.endAt, clampedAt)
                    active.firstOtherAppAt = nil
                    openByApp[musicApp] = active
                } else {
                    completedByApp[musicApp, default: []].append(active)
                    openByApp[musicApp] = OpenSession(
                        startAt: clampedAt,
                        endAt: clampedAt,
                        firstOtherAppAt: nil,
                        taintedByAgent: agentFlag
                    )
                }
            } else {
                openByApp[musicApp] = OpenSession(
                    startAt: clampedAt,
                    endAt: clampedAt,
                    firstOtherAppAt: nil,
                    taintedByAgent: agentFlag
                )
            }
        }

        for (musicApp, active) in openByApp {
            completedByApp[musicApp, default: []].append(active)
        }

        // Filter out agent-tainted and out-of-window sessions, then cap to at most 2 sessions per natural day.
        var validSessionsByApp: [String: [Session]] = [:]
        var weightedScoreByApp: [String: Double] = [:]

        for (musicApp, rawSessions) in completedByApp {
            let cleanInWindow = rawSessions.filter { session in
                guard !session.taintedByAgent else { return false }
                guard session.endAt >= windowFloor && session.endAt <= now else { return false }
                if let watermarkAt, session.startAt <= watermarkAt || session.endAt <= watermarkAt {
                    return false
                }
                return true
            }
            guard !cleanInWindow.isEmpty else { continue }

            var byDay: [Date: [OpenSession]] = [:]
            for session in cleanInWindow {
                let day = calendar.startOfDay(for: session.startAt)
                byDay[day, default: []].append(session)
            }

            var capped: [Session] = []
            for day in byDay.keys.sorted() {
                let sortedInDay = (byDay[day] ?? []).sorted { $0.endAt < $1.endAt }
                for kept in sortedInDay.suffix(maxSessionsPerDay) {
                    capped.append(Session(bundleID: musicApp, startAt: kept.startAt, endAt: kept.endAt))
                }
            }
            capped.sort { $0.endAt < $1.endAt }
            guard !capped.isEmpty else { continue }

            let score = capped.reduce(0.0) { partial, session in
                let age = max(0, now.timeIntervalSince(session.endAt))
                let weight = pow(0.5, age / decayHalfLifeSeconds)
                return partial + weight
            }
            if score > 0 {
                validSessionsByApp[musicApp] = capped
                weightedScoreByApp[musicApp] = score
            }
        }

        let totalWeight = weightedScoreByApp.values.reduce(0.0, +)
        guard totalWeight > 0 else { return nil }

        guard let (bestApp, bestWeight) = weightedScoreByApp.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }) else {
            return nil
        }

        let share = bestWeight / totalWeight
        // Guard against 1-ULP IEEE 754 rounding on exact 7:3 decayed sums while rejecting < 70%.
        guard share >= requiredWeightedShare - 1e-12 else {
            return nil
        }

        guard let bestSessions = validSessionsByApp[bestApp],
              bestSessions.count >= minActiveSessions,
              let earliest = bestSessions.first,
              let latest = bestSessions.last else {
            return nil
        }

        guard now.timeIntervalSince(latest.endAt) <= recentRequiredSeconds else {
            return nil
        }

        var latestEndByDay: [Date: Date] = [:]
        for session in bestSessions {
            let day = calendar.startOfDay(for: session.startAt)
            if let prev = latestEndByDay[day] {
                latestEndByDay[day] = max(prev, session.endAt)
            } else {
                latestEndByDay[day] = session.endAt
            }
        }
        let sortedDays = latestEndByDay.keys.sorted()
        guard sortedDays.count >= minDistinctDays else {
            return nil
        }

        let recencyExpiry = latest.endAt.addingTimeInterval(recentRequiredSeconds)
        let fifthMostRecentExpiry = bestSessions[bestSessions.count - minActiveSessions].endAt.addingTimeInterval(windowSeconds)
        let thirdMostRecentDay = sortedDays[sortedDays.count - minDistinctDays]
        let thirdDayExpiry = (latestEndByDay[thirdMostRecentDay] ?? latest.endAt).addingTimeInterval(windowSeconds)
        let expiresAt = min(recencyExpiry, min(fifthMostRecentExpiry, thirdDayExpiry))

        guard expiresAt > now else { return nil }

        return InferredMusicAppHabit(
            bundleID: bestApp,
            source: .screenHistoryLocalStats,
            windowStart: earliest.startAt,
            windowEnd: now,
            activeSessionCount: bestSessions.count,
            distinctDayCount: sortedDays.count,
            lastObservedAt: latest.endAt,
            weightedShare: min(1.0, share),
            computedAt: now,
            expiresAt: expiresAt
        )
    }
}
