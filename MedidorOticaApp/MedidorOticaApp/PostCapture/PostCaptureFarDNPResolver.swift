//
//  PostCaptureFarDNPResolver.swift
//  MedidorOticaApp
//
//  Converte DNP perto em DNP longe usando geometria de vergencia estavel.
//

import Foundation
import simd

// MARK: - Resultado da DNP longe
/// Resultado consolidado da conversao geometrica de DNP perto para longe.
struct PostCaptureFarDNPResult: Equatable {
    let rightDNPFar: Double
    let leftDNPFar: Double
    let confidence: Double
    let confidenceReason: String?
}

// MARK: - Resolver da DNP longe
/// Recalcula a DNP de longe a partir da distancia real da captura e da profundidade pupilar.
struct PostCaptureFarDNPResolver {
    private enum Constants {
        /// Profundidade optica plausivel entre o centro do olho e o centro aparente da pupila.
        static let minimumPupilDepthMeters: Float = 0.008
        static let maximumPupilDepthMeters: Float = 0.015
        static let defaultPupilDepthMeters: Float = 0.0115
        /// Faixa clinica plausivel da DNP monocular.
        static let minimumDNP: Double = 10
        static let maximumDNP: Double = 45
    }

    /// Resolve a DNP de longe usando uma conversao geometrica estavel, sem tabela fixa.
    static func resolve(rightPupilNear: NormalizedPoint,
                        leftPupilNear: NormalizedPoint,
                        centralPoint: NormalizedPoint,
                        scale: PostCaptureScale,
                        eyeGeometry: CaptureEyeGeometrySnapshot?) -> PostCaptureFarDNPResult {
        let near = nearDNP(rightPupil: rightPupilNear,
                           leftPupil: leftPupilNear,
                           centralPoint: centralPoint,
                           scale: scale)

        guard let eyeGeometry else {
            return PostCaptureFarDNPResult(rightDNPFar: near.right,
                                           leftDNPFar: near.left,
                                           confidence: 0,
                                           confidenceReason: "Geometria ocular 3D indisponivel nesta captura.")
        }

        let rightDepth = resolvedPupilDepthMeters(for: eyeGeometry.rightEye,
                                                  observedPupil: rightPupilNear,
                                                  fallbackDepth: nil)
        let leftDepth = resolvedPupilDepthMeters(for: eyeGeometry.leftEye,
                                                 observedPupil: leftPupilNear,
                                                 fallbackDepth: rightDepth)

        let rightFixationDistanceMM = max(Double(simd_length(eyeGeometry.rightEye.centerCamera.simdValue)) * 1000.0, 1)
        let leftFixationDistanceMM = max(Double(simd_length(eyeGeometry.leftEye.centerCamera.simdValue)) * 1000.0, 1)
        let rightFactor = distanceToFarFactor(fixationDistanceMM: rightFixationDistanceMM,
                                              pupilDepthMM: Double(rightDepth) * 1000.0)
        let leftFactor = distanceToFarFactor(fixationDistanceMM: leftFixationDistanceMM,
                                             pupilDepthMM: Double(leftDepth) * 1000.0)

        let correctedRight = clampedDNP(near.right * rightFactor)
        let correctedLeft = clampedDNP(near.left * leftFactor)
        let confidenceReason = eyeGeometry.isFixationReliable ? nil :
            (eyeGeometry.fixationConfidenceReason ?? "Fixacao na camera com confianca reduzida.")

        return PostCaptureFarDNPResult(rightDNPFar: correctedRight,
                                       leftDNPFar: correctedLeft,
                                       confidence: eyeGeometry.fixationConfidence,
                                       confidenceReason: confidenceReason)
    }

    // MARK: - Geometria de perto
    /// Mede as DNPs monoculares no plano optico atual.
    private static func nearDNP(rightPupil: NormalizedPoint,
                                leftPupil: NormalizedPoint,
                                centralPoint: NormalizedPoint,
                                scale: PostCaptureScale) -> (right: Double, left: Double) {
        let rightMidY = midpoint(rightPupil.y, centralPoint.y)
        let leftMidY = midpoint(leftPupil.y, centralPoint.y)
        let right = clampedDNP(scale.horizontalMillimeters(between: rightPupil.x,
                                                           and: centralPoint.x,
                                                           at: rightMidY))
        let left = clampedDNP(scale.horizontalMillimeters(between: leftPupil.x,
                                                          and: centralPoint.x,
                                                          at: leftMidY))
        return (right, left)
    }

    // MARK: - Conversao perto -> longe
    /// Converte a distancia de perto em longe por semelhanca de triangulos no plano do olho.
    private static func distanceToFarFactor(fixationDistanceMM: Double,
                                            pupilDepthMM: Double) -> Double {
        let effectiveDistance = max(fixationDistanceMM - pupilDepthMM, 1)
        let factor = fixationDistanceMM / effectiveDistance
        guard factor.isFinite else { return 1.0 }
        return max(factor, 1.0)
    }

    /// Estima a profundidade aparente da pupila usando a propria geometria do frame final.
    private static func resolvedPupilDepthMeters(for eye: CaptureEyeGeometrySnapshot.EyeSnapshot,
                                                 observedPupil: NormalizedPoint,
                                                 fallbackDepth: Float?) -> Float {
        guard let projection = eye.projection,
              let normalizedGaze = normalized(eye.gazeCamera.simdValue) else {
            return clampedPupilDepth(fallbackDepth ?? Constants.defaultPupilDepthMeters)
        }

        let clampedObserved = observedPupil.clamped()
        let projectedCenter = projection.projectedCenter
        let observedDelta = SIMD2<Double>(Double(clampedObserved.x - projectedCenter.x),
                                          Double(clampedObserved.y - projectedCenter.y))
        let projectedGazeDelta = SIMD2<Double>(
            Double(simd_dot(projection.normalizedXPerMeter.simdValue, normalizedGaze)),
            Double(simd_dot(projection.normalizedYPerMeter.simdValue, normalizedGaze))
        )
        let denominator = simd_dot(projectedGazeDelta, projectedGazeDelta)
        guard denominator.isFinite, denominator > 1e-6 else {
            return clampedPupilDepth(fallbackDepth ?? Constants.defaultPupilDepthMeters)
        }

        let solvedDepth = Float(simd_dot(observedDelta, projectedGazeDelta) / denominator)
        guard solvedDepth.isFinite else {
            return clampedPupilDepth(fallbackDepth ?? Constants.defaultPupilDepthMeters)
        }

        return clampedPupilDepth(solvedDepth)
    }

    // MARK: - Helpers
    private static func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length.isFinite, length > .ulpOfOne else { return nil }
        return vector / length
    }

    private static func midpoint(_ first: CGFloat,
                                 _ second: CGFloat) -> CGFloat {
        (first + second) * 0.5
    }

    private static func clampedPupilDepth(_ value: Float) -> Float {
        min(max(value, Constants.minimumPupilDepthMeters), Constants.maximumPupilDepthMeters)
    }

    private static func clampedDNP(_ value: Double) -> Double {
        min(max(value, Constants.minimumDNP), Constants.maximumDNP)
    }
}
