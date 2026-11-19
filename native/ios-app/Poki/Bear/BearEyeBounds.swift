import Foundation
import simd

/// Geometric containment and curved-surface tracking for the bear's pupils.
///
/// Each pupil is a curved patch resting just outside its white eye pad on the head sphere. Linear
/// translation pushes a pupil either through the curved white pad or out past the elliptical sclera
/// rim when the head turns. Rotating each pupil around the head's center keeps constant clearance
/// over the sclera, while per-eye elliptical clamping guarantees every pupil stays inside its visible
/// white sclera at every gaze, head angle, blink frame, and expression.
enum BearEyeBounds {
    enum Side: CaseIterable { case right, left }

    struct EyeGeometry {
        /// Visible EyePad ellipse center and semi-axes (mask >= 0.50, measured from PokiBear.usdz frame 95).
        let scleraCenter: SIMD2<Float>
        let scleraRadii: SIMD2<Float>
        /// Rest Pupil center and semi-axes in model space (frame 95).
        let pupilRestCenter: SIMD2<Float>
        let pupilRadii: SIMD2<Float>
        /// Bone origin in Head-relative model space (X right, Y up, Z forward).
        let boneOrigin: SIMD3<Float>
    }

    struct SphericalTransform: Equatable {
        /// Clamped pupil center displacement along the face plane.
        var clampedDelta: SIMD2<Float>
        /// Joint translation delta to rotate smoothly over the head surface.
        var translation: SIMD3<Float>
        /// Joint rotation aligning the curved pupil patch with the head curvature.
        var rotation: simd_quatf
    }

    /// Head sphere center in model space (Y up, Z forward), fitted to `Head_001` front face.
    static let headCenter = SIMD3<Float>(-0.015, 0.895, 0.010)
    /// Lower rim Y of the thinking squinting eyelid over `Eye_L` (viewer right).
    static let thinkingLidBottomY: Float = 0.998

    static let right = EyeGeometry(
        scleraCenter: SIMD2(-0.18083, 0.90705),
        scleraRadii: SIMD2(0.13107, 0.14747),
        pupilRestCenter: SIMD2(-0.13633, 0.91185),
        pupilRadii: SIMD2(0.08486, 0.08862),
        boneOrigin: SIMD3(-0.1833, 0.9107, 0.4224)
    )

    static let left = EyeGeometry(
        scleraCenter: SIMD2(0.17619, 0.90072),
        scleraRadii: SIMD2(0.13008, 0.14743),
        pupilRestCenter: SIMD2(0.13239, 0.90876),
        pupilRadii: SIMD2(0.08494, 0.08923),
        boneOrigin: SIMD3(0.1787, 0.9054, 0.4075)
    )

    static func geometry(for side: Side) -> EyeGeometry {
        side == .right ? right : left
    }

    /// Computes coordinated, strictly contained spherical eye transforms for both eyes.
    static func transforms(
        desiredGaze: SIMD2<Float>,
        headYaw: Float,
        headPitch: Float,
        thinkingLid: Float,
        blinkAttenuation: Float = 1
    ) -> (right: SphericalTransform, left: SphericalTransform) {
        let g = desiredGaze * min(max(blinkAttenuation, 0), 1)
        let leftLidLimit: Float? = thinkingLid > 0.05
            ? simd_mix(left.scleraCenter.y + left.scleraRadii.y, thinkingLidBottomY, min(thinkingLid, 1))
            : nil

        var deltaR = clampXY(side: .right, desired: g, headYaw: headYaw, headPitch: headPitch, lidTopLimit: nil)
        var deltaL = clampXY(side: .left, desired: g, headYaw: headYaw, headPitch: headPitch, lidTopLimit: leftLidLimit)

        // When the thinking eyelid lowers the left eye's vertical ceiling, match both eyes' vertical gaze
        // so the bear does not look cross-eyed vertically.
        if thinkingLid > 0.05 {
            let sharedY = min(deltaR.y, deltaL.y)
            deltaR = clampXY(side: .right, desired: SIMD2(g.x, sharedY), headYaw: headYaw, headPitch: headPitch, lidTopLimit: nil)
            deltaL = clampXY(side: .left, desired: SIMD2(g.x, sharedY), headYaw: headYaw, headPitch: headPitch, lidTopLimit: leftLidLimit)
        }

        return (
            right: spherical(side: .right, delta: deltaR),
            left: spherical(side: .left, delta: deltaL)
        )
    }

    /// Clamps a single eye's desired `(dx, dy)` displacement so every point on the pupil's boundary
    /// stays strictly inside its visible white sclera ellipse and below any active upper eyelid.
    static func clampXY(
        side: Side,
        desired: SIMD2<Float>,
        headYaw: Float,
        headPitch: Float,
        lidTopLimit: Float?
    ) -> SIMD2<Float> {
        let geo = geometry(for: side)
        let yawMag = abs(headYaw)
        let pitchMag = abs(headPitch)

        // Preserve the model's authored rest gaze cleanly when looking straight ahead at rest;
        // enforce a visible white margin and extra turn-angle parallax cushion whenever moving or turning.
        let moving = simd_length(desired) > 1e-4 || yawMag > 0.02 || pitchMag > 0.02 || lidTopLimit != nil
        if !moving { return .zero }

        let marginX: Float = 0.0032 + 0.0065 * yawMag
        let marginY: Float = 0.0040 + 0.0065 * pitchMag
        let availX = max(0.006, geo.scleraRadii.x - geo.pupilRadii.x - marginX)
        let availY = max(0.006, geo.scleraRadii.y - geo.pupilRadii.y - marginY)

        var cx = geo.pupilRestCenter.x + desired.x
        var cy = geo.pupilRestCenter.y + desired.y

        if let lidTop = lidTopLimit {
            cy = min(cy, lidTop - geo.pupilRadii.y - 0.0025)
        }

        var u = (cx - geo.scleraCenter.x) / availX
        var v = (cy - geo.scleraCenter.y) / availY
        if u * u + v * v > 1 {
            v = min(max(v, -0.98), 0.98)
            let uLim = sqrt(max(0, 1 - v * v))
            u = min(max(u, -uLim), uLim)
            cx = geo.scleraCenter.x + u * availX
            cy = geo.scleraCenter.y + v * availY
        }

        return SIMD2(cx - geo.pupilRestCenter.x, cy - geo.pupilRestCenter.y)
    }

    /// Converts an in-plane clamped `(dx, dy)` displacement into a spherical rotation around `headCenter`
    /// so the curved pupil tracks the curved sclera with uniform surface clearance.
    static func spherical(side: Side, delta: SIMD2<Float>) -> SphericalTransform {
        let mag = simd_length(delta)
        if mag < 1e-6 {
            return SphericalTransform(clampedDelta: .zero, translation: .zero, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]))
        }
        let geo = geometry(for: side)
        let r = geo.boneOrigin - headCenter
        let radiusXZ = hypot(r.x, r.z)
        let radiusYZ = hypot(r.y, r.z)
        let yaw = delta.x / radiusXZ
        let pitch = -delta.y / radiusYZ
        let rot = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        let rotated = rot.act(r)
        // Radial surface clearance scales smoothly with displacement so the curved pupil patch
        // never dips into the curved sclera even during vertical or diagonal gaze.
        let outward = simd_normalize(rotated)
        let clearance = min(mag / 0.010, 1) * Float(0.0046)
        let dt = (rotated - r) + outward * clearance
        return SphericalTransform(clampedDelta: delta, translation: dt, rotation: rot)
    }

    /// Minimum normalized clearance from the pupil perimeter to the visible sclera ellipse (> 0 means
    /// all 36 sampled points around the pupil rim lie strictly inside the white sclera).
    static func minNormalizedClearance(
        side: Side,
        delta: SIMD2<Float>,
        lidTopLimit: Float? = nil
    ) -> Float {
        let geo = geometry(for: side)
        let center = geo.pupilRestCenter + delta
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
