import Foundation
import simd

/// Geometric containment and synchronized curved-surface tracking for the bear's pupils.
///
/// Both eyes are driven by a single shared gaze displacement computed inside the intersection of
/// both eyes' visible white sclera ellipses (plus any active upper eyelid limit). A small symmetric
/// baseline recentering (`±baseCenterShiftX`) opens a balanced shared gaze basin while preserving
/// the bear's signature cute rest look, so both pupils always move in exact unison by the same
/// vector, never diverge or oppose each other, and never clip outside their white sclera.
enum BearEyeBounds {
    enum Side: CaseIterable { case right, left }

    struct EyeGeometry {
        /// Visible EyePad ellipse center and semi-axes (mask >= 0.50, measured from PokiBear.usdz frame 95).
        let scleraCenter: SIMD2<Float>
        let scleraRadii: SIMD2<Float>
        /// Authored rest Pupil center and semi-axes in model space (frame 95).
        let pupilRestCenter: SIMD2<Float>
        let pupilRadii: SIMD2<Float>
        /// Bone origin in Head-relative model space (X right, Y up, Z forward).
        let boneOrigin: SIMD3<Float>
        /// Symmetric baseline recentering offset so both eyes share a wide synchronized gaze basin.
        let baselineShiftX: Float
    }

    struct SphericalTransform: Equatable {
        /// Shared dynamic gaze displacement from the synchronized neutral position (identical for both eyes).
        var gazeDelta: SIMD2<Float>
        /// Total displacement from the authored frame-95 rest mesh (`baselineShiftX + gazeDelta.x`, `gazeDelta.y`).
        var totalDelta: SIMD2<Float>
        /// Joint translation delta to rotate smoothly over the head surface.
        var translation: SIMD3<Float>
        /// Joint rotation aligning the curved pupil patch with the head curvature.
        var rotation: simd_quatf
    }

    /// Head sphere center in model space (Y up, Z forward), fitted to `Head_001` front face.
    static let headCenter = SIMD3<Float>(-0.015, 0.895, 0.010)
    /// Lower rim Y of the thinking squinting eyelid over `Eye_L` (viewer right).
    static let thinkingLidBottomY: Float = 0.998
    /// Symmetric outward shift from authored inner-corner rest so left and right eyes share ±16 mm of
    /// synchronized horizontal travel inside their white sclera.
    static let baseCenterShiftX: Float = 0.018

    static let right = EyeGeometry(
        scleraCenter: SIMD2(-0.18083, 0.90705),
        scleraRadii: SIMD2(0.13107, 0.14747),
        pupilRestCenter: SIMD2(-0.13633, 0.91185),
        pupilRadii: SIMD2(0.08486, 0.08862),
        boneOrigin: SIMD3(-0.1833, 0.9107, 0.4224),
        baselineShiftX: -baseCenterShiftX
    )

    static let left = EyeGeometry(
        scleraCenter: SIMD2(0.17619, 0.90072),
        scleraRadii: SIMD2(0.13008, 0.14743),
        pupilRestCenter: SIMD2(0.13239, 0.90876),
        pupilRadii: SIMD2(0.08494, 0.08923),
        boneOrigin: SIMD3(0.1787, 0.9054, 0.4075),
        baselineShiftX: baseCenterShiftX
    )

    static func geometry(for side: Side) -> EyeGeometry {
        side == .right ? right : left
    }

    /// Computes strictly synchronized, strictly contained spherical eye transforms for both eyes.
    /// Both returned transforms always carry the exact same `gazeDelta`.
    static func transforms(
        desiredGaze: SIMD2<Float>,
        headYaw: Float,
        headPitch: Float,
        thinkingLid: Float
    ) -> (right: SphericalTransform, left: SphericalTransform) {
        let shared = clampSharedGaze(
            desired: desiredGaze,
            headYaw: headYaw,
            headPitch: headPitch,
            thinkingLid: thinkingLid
        )
        return (
            right: spherical(side: .right, gazeDelta: shared),
            left: spherical(side: .left, gazeDelta: shared)
        )
    }

    /// Clamps a single desired gaze vector into the intersection of both eyes' safe sclera ellipses
    /// (and below any active thinking eyelid), preserving exact gaze direction for both eyes together.
    static func clampSharedGaze(
        desired: SIMD2<Float>,
        headYaw: Float,
        headPitch: Float,
        thinkingLid: Float
    ) -> SIMD2<Float> {
        let yawMag = abs(headYaw)
        let pitchMag = abs(headPitch)
        let marginX: Float = 0.0035 + 0.0060 * yawMag
        let marginY: Float = 0.0040 + 0.0060 * pitchMag

        let leftLidLimit: Float? = thinkingLid > 0.05
            ? simd_mix(left.scleraCenter.y + left.scleraRadii.y, thinkingLidBottomY, min(thinkingLid, 1))
            : nil

        func fits(_ delta: SIMD2<Float>) -> Bool {
            for side in Side.allCases {
                let geo = geometry(for: side)
                let availX = max(0.006, geo.scleraRadii.x - geo.pupilRadii.x - marginX)
                let availY = max(0.006, geo.scleraRadii.y - geo.pupilRadii.y - marginY)
                let cx = geo.pupilRestCenter.x + geo.baselineShiftX + delta.x
                let cy = geo.pupilRestCenter.y + delta.y
                if side == .left, let lidTop = leftLidLimit, cy > lidTop - geo.pupilRadii.y - 0.0025 {
                    return false
                }
                let u = (cx - geo.scleraCenter.x) / availX
                let v = (cy - geo.scleraCenter.y) / availY
                if u * u + v * v > 1 { return false }
            }
            return true
        }

        // Compute the shared vertical ceiling (identical for both eyes) so thinking eyelid lowers both together.
        var maxDeltaY: Float = 0.045
        if let lidTop = leftLidLimit {
            maxDeltaY = min(maxDeltaY, (lidTop - left.pupilRadii.y - 0.0025) - left.pupilRestCenter.y)
        }
        let target = SIMD2<Float>(desired.x, min(desired.y, maxDeltaY))
        if fits(target) { return target }

        // Safe synchronized anchor point guaranteed inside both ellipses (only shifts vertically if lid demands it).
        let anchor = SIMD2<Float>(0, min(0, maxDeltaY))
        if !fits(anchor) { return SIMD2<Float>(0, min(-0.008, maxDeltaY)) }

        // Binary-search largest fraction along anchor -> target that keeps both eyes strictly inside their sclera.
        var lo: Float = 0
        var hi: Float = 1
        for _ in 0..<18 {
            let mid = 0.5 * (lo + hi)
            let candidate = anchor + (target - anchor) * mid
            if fits(candidate) { lo = mid } else { hi = mid }
        }
        return anchor + (target - anchor) * lo
    }

    /// Converts a synchronized `gazeDelta` (plus this eye's symmetric `baselineShiftX`) into a
    /// spherical rotation around `headCenter` so the curved pupil hugs the curved sclera cleanly.
    static func spherical(side: Side, gazeDelta: SIMD2<Float>, includeBaseline: Bool = true) -> SphericalTransform {
        let geo = geometry(for: side)
        let total = SIMD2<Float>((includeBaseline ? geo.baselineShiftX : 0) + gazeDelta.x, gazeDelta.y)
        let mag = simd_length(total)
        if mag < 1e-6 {
            return SphericalTransform(
                gazeDelta: gazeDelta,
                totalDelta: .zero,
                translation: .zero,
                rotation: simd_quatf(angle: 0, axis: [0, 1, 0])
            )
        }
        let r = geo.boneOrigin - headCenter
        let radiusXZ = hypot(r.x, r.z)
        let radiusYZ = hypot(r.y, r.z)
        let yaw = total.x / radiusXZ
        let pitch = -total.y / radiusYZ
        let rot = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        let rotated = rot.act(r)
        let outward = simd_normalize(rotated)
        let clearance = min(mag / 0.010, 1) * Float(0.0046)
        let dt = (rotated - r) + outward * clearance
        return SphericalTransform(gazeDelta: gazeDelta, totalDelta: total, translation: dt, rotation: rot)
    }

    /// Minimum normalized clearance from the pupil perimeter to the visible sclera ellipse (> 0 means
    /// all 36 sampled points around the pupil rim lie strictly inside the white sclera).
    static func minNormalizedClearance(
        side: Side,
        totalDelta: SIMD2<Float>,
        lidTopLimit: Float? = nil
    ) -> Float {
        let geo = geometry(for: side)
        let center = geo.pupilRestCenter + totalDelta
        var worst: Float = .greatestFiniteMagnitude
        for step in 0..<36 {
            let theta = Float(step) * (2 * .pi / 36)
            let px = center.x + geo.pupilRadii.x * cos(theta)
            let py = center.y + geo.pupilRadii.y * sin(theta)
            let nx = (px - geo.scleraCenter.x) / geo.scleraRadii.x
            let ny = (py - geo.scleraCenter.y) / geo.scleraRadii.y
            worst = min(worst, 1 - hypot(nx, ny))
            if let lidTop = lidTopLimit {
                worst = min(worst, (lidTop - py) / geo.scleraRadii.y)
            }
        }
        return worst
    }
}
