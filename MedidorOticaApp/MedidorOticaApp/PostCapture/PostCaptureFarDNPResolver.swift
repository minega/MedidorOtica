//
//  PostCaptureFarDNPResolver.swift
//  MedidorOticaApp
//
//  Reprojeta a pupila no proprio frame capturado para calcular DNP perto e longe.
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
/// Recalcula a DNP de longe reprojetando a pupila no mesmo frame da captura.
struct PostCaptureFarDNPResolver {
    private struct ReprojectedEyeState {
        let pupilDepthMeters: Float
        let nearProjectedPupil: NormalizedPoint
        let farProjectedPupil: NormalizedPoint
    }

    private enum Constants {
        /// Profundidade otica plausivel entre o centro do olho e o centro aparente da pupila.
        static let minimumPupilDepthMeters: Float = 0.006
        static let maximumPupilDepthMeters: Float = 0.018
        static let defaultPupilDepthMeters: Float = 0.0115
        /// Evita divisao por zero quando a projecao local fica muito plana.
        static let minimumProjectionMagnitude: Double = 1e-6
        /// Mantem a DNP dentro da faixa clinica esperada.
        static let minimumDNP: Double = 10
        static let maximumDNP: Double = 45
        /// Garante uma abertura minima entre perto e longe para nao colapsar as medidas.
        static let minimumTotalFarDeltaMM: Double = 0.8
    }

    /// Resolve a DNP de longe a partir dos pontos reais da mesma foto.
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

        let farDirection = resolvedFarDirection(using: eyeGeometry)
        let rightState = reprojectedEyeState(eye: eyeGeometry.rightEye,
                                             observedPupil: rightPupilNear,
                                             fallbackDepth: nil,
                                             farDirection: farDirection)
        let leftState = reprojectedEyeState(eye: eyeGeometry.leftEye,
                                            observedPupil: leftPupilNear,
                                            fallbackDepth: rightState?.pupilDepthMeters,
                                            farDirection: farDirection)
        let stabilizedRightState = stabilizedState(primary: rightState,
                                                   fallbackDepth: leftState?.pupilDepthMeters,
                                                   eye: eyeGeometry.rightEye,
                                                   observedPupil: rightPupilNear,
                                                   farDirection: farDirection)
        let stabilizedLeftState = stabilizedState(primary: leftState,
                                                  fallbackDepth: rightState?.pupilDepthMeters,
                                                  eye: eyeGeometry.leftEye,
                                                  observedPupil: leftPupilNear,
                                                  farDirection: farDirection)

        guard let rightState = stabilizedRightState,
              let leftState = stabilizedLeftState else {
            return PostCaptureFarDNPResult(rightDNPFar: near.right,
                                           leftDNPFar: near.left,
                                           confidence: eyeGeometry.fixationConfidence,
                                           confidenceReason: "Nao foi possivel reprojetar a pupila com confianca.")
        }

        let rawFar = nearDNP(rightPupil: rightState.farProjectedPupil,
                             leftPupil: leftState.farProjectedPupil,
                             centralPoint: centralPoint,
                             scale: scale)
        let correctedFar = enforceMinimumFarDelta(near: near,
                                                  far: rawFar,
                                                  rightNearPoint: rightPupilNear,
                                                  leftNearPoint: leftPupilNear,
                                                  centralPoint: centralPoint,
                                                  scale: scale)
        let confidenceReason = eyeGeometry.isFixationReliable ? nil :
            (eyeGeometry.fixationConfidenceReason ?? "Fixacao na camera com confianca reduzida.")

        return PostCaptureFarDNPResult(rightDNPFar: correctedFar.right,
                                       leftDNPFar: correctedFar.left,
                                       confidence: eyeGeometry.fixationConfidence,
                                       confidenceReason: confidenceReason)
    }

    // MARK: - Reprojecao da pupila
    /// Reconstrui a profundidade da pupila observada e reprojeta o mesmo olho para longe.
    private static func reprojectedEyeState(eye: CaptureEyeGeometrySnapshot.EyeSnapshot,
                                            observedPupil: NormalizedPoint,
                                            fallbackDepth: Float?,
                                            farDirection: SIMD3<Float>) -> ReprojectedEyeState? {
        guard let projection = eye.projection else { return nil }
        let gaze = eye.gazeCamera.simdValue
        guard let normalizedGaze = normalized(gaze) else { return nil }

        let pupilDepth = resolvedPupilDepthMeters(projection: projection,
                                                  observedPupil: observedPupil,
                                                  gaze: normalizedGaze,
                                                  fallbackDepth: fallbackDepth)
        let nearDelta = normalizedGaze * pupilDepth
        let farDelta = farDirection * pupilDepth

        return ReprojectedEyeState(pupilDepthMeters: pupilDepth,
                                   nearProjectedPupil: projection.projectedPoint(for: nearDelta),
                                   farProjectedPupil: projection.projectedPoint(for: farDelta))
    }

    /// Garante um estado valido mesmo quando um dos olhos falhar na solucao principal.
    private static func stabilizedState(primary: ReprojectedEyeState?,
                                        fallbackDepth: Float?,
                                        eye: CaptureEyeGeometrySnapshot.EyeSnapshot,
                                        observedPupil: NormalizedPoint,
                                        farDirection: SIMD3<Float>) -> ReprojectedEyeState? {
        if let primary {
            return primary
        }

        guard let projection = eye.projection,
              let normalizedGaze = normalized(eye.gazeCamera.simdValue) else {
            return nil
        }

        let depth = clampedPupilDepth(fallbackDepth ?? Constants.defaultPupilDepthMeters)
        let nearDelta = normalizedGaze * depth
        let farDelta = farDirection * depth
        return ReprojectedEyeState(pupilDepthMeters: depth,
                                   nearProjectedPupil: observedPupil.clamped(),
                                   farProjectedPupil: projection.projectedPoint(for: farDelta))
    }

    /// Resolve a profundidade aparente da pupila a partir da propria imagem observada.
    private static func resolvedPupilDepthMeters(projection: CaptureEyeGeometrySnapshot.LinearizedProjection,
                                                 observedPupil: NormalizedPoint,
                                                 gaze: SIMD3<Float>,
                                                 fallbackDepth: Float?) -> Float {
        let clampedObserved = observedPupil.clamped()
        let projectedCenter = projection.projectedCenter
        let observedDelta = SIMD2<Double>(Double(clampedObserved.x - projectedCenter.x),
                                          Double(clampedObserved.y - projectedCenter.y))
        let projectedGazeDelta = SIMD2<Double>(
            Double(simd_dot(projection.normalizedXPerMeter.simdValue, gaze)),
            Double(simd_dot(projection.normalizedYPerMeter.simdValue, gaze))
        )

        let denominator = simd_dot(projectedGazeDelta, projectedGazeDelta)
        guard denominator.isFinite, denominator >= Constants.minimumProjectionMagnitude else {
            return clampedPupilDepth(fallbackDepth ?? Constants.defaultPupilDepthMeters)
        }

        let solvedDepth = Float(simd_dot(observedDelta, projectedGazeDelta) / denominator)
        guard solvedDepth.isFinite else {
            return clampedPupilDepth(fallbackDepth ?? Constants.defaultPupilDepthMeters)
        }

        return clampedPupilDepth(solvedDepth)
    }

    /// Resolve a direcao de longe preservando a pose media da cabeca sem convergencia de perto.
    private static func resolvedFarDirection(using eyeGeometry: CaptureEyeGeometrySnapshot) -> SIMD3<Float> {
        if let faceForward = eyeGeometry.faceForwardCamera?.simdValue,
           let normalizedFaceForward = normalized(faceForward) {
            return normalizedFaceForward
        }

        let leftGaze = eyeGeometry.leftEye.gazeCamera.simdValue
        let rightGaze = eyeGeometry.rightEye.gazeCamera.simdValue
        let meanGaze = normalized(leftGaze + rightGaze)

        let leftEyeCenter = eyeGeometry.leftEye.centerCamera.simdValue
        let rightEyeCenter = eyeGeometry.rightEye.centerCamera.simdValue
        let midpointDirection = normalized(-((leftEyeCenter + rightEyeCenter) * 0.5))

        if let meanGaze, let midpointDirection {
            return normalized(meanGaze + midpointDirection) ?? midpointDirection
        }

        return meanGaze ?? midpointDirection ?? SIMD3<Float>(0, 0, 1)
    }

    // MARK: - Medicao
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

    /// Evita que a DNP longe colapse novamente para o mesmo valor da DNP perto.
    private static func enforceMinimumFarDelta(near: (right: Double, left: Double),
                                               far: (right: Double, left: Double),
                                               rightNearPoint: NormalizedPoint,
                                               leftNearPoint: NormalizedPoint,
                                               centralPoint: NormalizedPoint,
                                               scale: PostCaptureScale) -> (right: Double, left: Double) {
        let currentTotalDelta = max((far.right + far.left) - (near.right + near.left), 0)
        guard currentTotalDelta < Constants.minimumTotalFarDeltaMM else {
            return (clampedDNP(far.right), clampedDNP(far.left))
        }

        let missingDelta = Constants.minimumTotalFarDeltaMM - currentTotalDelta
        let rightDistance = abs(rightNearPoint.x - centralPoint.x)
        let leftDistance = abs(leftNearPoint.x - centralPoint.x)
        let totalDistance = max(rightDistance + leftDistance, .ulpOfOne)
        let rightWeight = Double(rightDistance / totalDistance)
        let leftWeight = 1 - rightWeight

        let correctedRight = clampedDNP(far.right + (missingDelta * rightWeight))
        let correctedLeft = clampedDNP(far.left + (missingDelta * leftWeight))
        return (correctedRight, correctedLeft)
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
