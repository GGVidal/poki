import XCTest
import simd
@testable import Poki

/// The bear standing on its own: breathes organically, shifts weight, darts eyes, and never clips
/// its pupils outside its white sclera.
final class BearIdleTests: XCTestCase {
    private func headTurn(_ pose: BearIdle.Pose) -> Float { max(abs(pose.headYaw), abs(pose.headPitch), abs(pose.headRoll)) }

    /// Thirty seconds without a touch, at the rate it is drawn: it breathes all along, shifts weight,
    /// and looks somewhere more than once.
    func testTheBearMovesByItselfWhileItStands() {
        var idle = BearIdle(now: 0)
        var lifts: [Float] = [], shifts: [Float] = [], looks = 0, looking = false
        for frame in 0..<900 {
            let pose = idle.pose(at: Double(frame) / 30)
            lifts.append(pose.bodyLift)
            shifts.append(pose.bodyShiftX)
            let turned = headTurn(pose) > 0.1
            if turned, !looking { looks += 1 }
            looking = turned
        }
        XCTAssertGreaterThan(lifts.max()! - lifts.min()!, 0.010, "it breathes")
        XCTAssertGreaterThan(shifts.max()! - shifts.min()!, 0.010, "it shifts weight")
        XCTAssertGreaterThanOrEqual(looks, 2, "it looks about")
    }

    /// A tap while it looks away: the head comes back before the hi.
    func testAHiBringsTheHeadBackFirst() throws {
        var idle = BearIdle(now: 0)
        var t = 0.0
        while headTurn(idle.pose(at: t)) < 0.12 {
            t += 1.0 / 30
            try XCTSkipIf(t > 30, "no look in thirty seconds")
        }
        idle.attend(at: t)
        let back = idle.pose(at: t + 0.35)
        XCTAssertLessThan(headTurn(back), 0.06)
    }

    /// Small gestures take turns: each once in every four, in a new order, never the same twice in a row.
    func testTheSmallThingsTakeTurns() {
        var idle = BearIdle(now: 0)
        let done = (0..<40).map { _ in idle.nextGesture() }
        for (a, b) in zip(done, done.dropFirst()) { XCTAssertNotEqual(a, b) }
        for start in stride(from: 0, to: 40, by: 4) {
            XCTAssertEqual(Set(done[start..<start + 4]), Set(BearIdle.Gesture.allCases), "turn from \(start)")
        }
    }

    /// Pupils always move in exact unison by the same gaze vector, never oppose each other, and
    /// remain strictly inside their white sclera across extreme gazes, head angles, blinks, and thinking.
    func testPupilsNeverLeaveWhiteScleraAcrossAnglesAndExpressions() {
        let gazes: [SIMD2<Float>] = [
            SIMD2(0.011, 0.012), SIMD2(-0.011, 0.012), // thinking gaze that previously clipped
            SIMD2(0.06, 0.06), SIMD2(-0.06, 0.06), SIMD2(0.06, -0.06), SIMD2(-0.06, -0.06),
            SIMD2(0.03, 0), SIMD2(-0.03, 0), SIMD2(0, 0.04), SIMD2(0, -0.04),
            BearStance.pose(.thinking).gaze,
        ]
        let yaws: [Float] = [-0.35, -0.20, 0, 0.20, 0.35]
        let pitches: [Float] = [-0.20, 0, 0.20]
        for thinking in [Float(0), 1] {
            let leftLid: Float? = thinking > 0.5 ? BearEyeBounds.thinkingLidBottomY : nil
            for yaw in yaws {
                for pitch in pitches {
                    for gaze in gazes {
                        let tr = BearEyeBounds.transforms(
                            desiredGaze: gaze,
                            headYaw: yaw,
                            headPitch: pitch,
                            thinkingLid: thinking
                        )
                        XCTAssertEqual(tr.right.gazeDelta, tr.left.gazeDelta, "eyes must move identically in sync")
                        if gaze.x > 0 { XCTAssertGreaterThanOrEqual(tr.right.gazeDelta.x, 0, "right gaze must not push eye left") }
                        if gaze.x < 0 { XCTAssertLessThanOrEqual(tr.right.gazeDelta.x, 0, "left gaze must not push eye right") }
                        let clearR = BearEyeBounds.minNormalizedClearance(side: .right, totalDelta: tr.right.totalDelta)
                        let clearL = BearEyeBounds.minNormalizedClearance(side: .left, totalDelta: tr.left.totalDelta, lidTopLimit: leftLid)
                        XCTAssertGreaterThan(clearR, 0, "Eye_R clipped at gaze=\(gaze) yaw=\(yaw) pitch=\(pitch) think=\(thinking)")
                        XCTAssertGreaterThan(clearL, 0, "Eye_L clipped at gaze=\(gaze) yaw=\(yaw) pitch=\(pitch) think=\(thinking)")
                    }
                }
            }
        }
        // Verify thinking gaze visibly shifts both eyes together in the same direction.
        let thinkTr = BearEyeBounds.transforms(
            desiredGaze: BearStance.pose(.thinking).gaze,
            headYaw: BearStance.pose(.thinking).headYaw,
            headPitch: BearStance.pose(.thinking).headPitch,
            thinkingLid: 1
        )
        XCTAssertEqual(thinkTr.right.gazeDelta, thinkTr.left.gazeDelta)
        XCTAssertGreaterThan(thinkTr.right.gazeDelta.x, 0.010, "both eyes should look right together while thinking")
    }

    /// The pupils glide: standing at the home screen for ten minutes, neither pupil ever moves faster than
    /// 0.18 model units a second (the sclera's room is about 0.03), at the rate it is drawn when it
    /// moves (60 Hz) and when it is calm (30 Hz). Before, the eyes darted 0.03 across in 0.12 s and
    /// were cut off in a single frame when a look began: up to 0.45 a second, which is the twitch.
    func testThePupilsNeverTwitchWhileTheBearStands() {
        for rate in [60.0, 30.0] {
            var idle = BearIdle(now: 0)
            var filter = BearPoseFilter()
            var previous: (right: SIMD3<Float>, left: SIMD3<Float>)?
            var fastest: Float = 0
            for frame in 0..<Int(600 * rate) {
                let now = Double(frame) / rate
                let pose = filter.filter(idle.pose(at: now), at: now)
                let eyes = BearEyeBounds.transforms(desiredGaze: pose.gaze, headYaw: pose.headYaw, headPitch: pose.headPitch, thinkingLid: pose.thinkExpression)
                if let before = previous {
                    let moved = max(simd_length(eyes.right.translation - before.right), simd_length(eyes.left.translation - before.left))
                    fastest = max(fastest, moved * Float(rate))
                }
                previous = (eyes.right.translation, eyes.left.translation)
            }
            XCTAssertLessThan(fastest, 0.18, "fastest pupil speed at \(rate) Hz, in model units a second")
        }
    }

    /// Second-order spring dynamics produce subtle anticipation and elastic overshoot on transitions
    /// without diverging or jumping across variable frame rates.
    func testSpringFilterProducesAnticipationAndOvershootWithoutJumping() {
        var spring = SecondOrderSpring(.arms, initial: 0)
        var minVal: Float = 0
        var maxVal: Float = 0
        let rampDuration = 0.24
        for step in 1...120 {
            let t = Double(step) / 60.0
            let target = BearIdle.ease(Float(t / rampDuration))
            let val = spring.step(dt: 1.0 / 60.0, target: target)
            minVal = min(minVal, val)
            maxVal = max(maxVal, val)
        }
        XCTAssertLessThan(minVal, -0.002, "expected subtle anticipation dip before rising")
        XCTAssertGreaterThan(maxVal, 1.04, "expected elastic overshoot past target")
        XCTAssertEqual(spring.value, 1.0, accuracy: 0.01, "expected spring to settle cleanly at target")
    }
}
