//
//  PostCaptureFarDNPResolver.swift
//  MedidorOticaApp
//
//  Converte DNP perto em DNP longe usando a geometria ocular real da mesma captura.
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
/// Recalcula a DNP de longe removendo apenas a componente convergente da captura.
struct PostCaptureFarDNPResolver {
    private enum Constants {
        /// Evita divisao por zero ao interceptar o plano do PC.
        static let minimumPlaneDirectionZ: Float = 0.02
        /// Mantem a conversao dentro de um intervalo optico plausivel por olho.
        static let minimumDNP: Double = 10
        static let maximumDNP: Double = 45
        /// Peso minimo para nao perder completamente um lado em situacoes assimetricas.
        static let minimumWeight = 0.2
        /// Garante um deslocamento minimo detectavel quando o frame estiver muito plano.
        static let minimumFarDeltaMM: Double = 0.15
    }

    /// Resolve a DNP de longe usando a mesma captura e sem tabela fixa.
    static func resolve(rightDNPNear: Double,
                        leftDNPNear: Double,
                        eyeGeometry: CaptureEyeGeometrySnapshot?) -> PostCaptureFarDNPResult {
        guard let eyeGeometry else {
            return PostCaptureFarDNPResult(rightDNPFar: rightDNPNear,
                                           leftDNPFar: leftDNPNear,
                                           confidence: 0,
                                           confidenceReason: "Geometria ocular 3D indisponivel nesta captura.")
        }

        guard let nearGeometry = nearGeometricDNP(using: eyeGeometry),
              let farGeometry = farGeometricDNP(using: eyeGeometry) else {
            return PostCaptureFarDNPResult(rightDNPFar: rightDNPNear,
                                           leftDNPFar: leftDNPNear,
                                           confidence: eyeGeometry.fixationConfidence,
                                           confidenceReason: "Nao foi possivel reconstruir a vergencia com confianca.")
        }

        let rawRightDelta = farGeometry.right - nearGeometry.right
        let rawLeftDelta = farGeometry.left - nearGeometry.left
        let rawTotalDelta = rawRightDelta + rawLeftDelta
        let fallbackTotalDelta = fallbackGeometricDelta(using: eyeGeometry)
        let appliedTotalDelta = max(rawTotalDelta, fallbackTotalDelta, Constants.minimumFarDeltaMM)
        let rightWeight = normalizedWeight(primary: rawRightDelta,
                                           secondary: rawLeftDelta)
        let leftWeight = 1 - rightWeight

        let correctedRight = clampedDNP(rightDNPNear + (appliedTotalDelta * rightWeight))
        let correctedLeft = clampedDNP(leftDNPNear + (appliedTotalDelta * leftWeight))

        let confidenceReason = eyeGeometry.isFixationReliable ? nil :
            (eyeGeometry.fixationConfidenceReason ?? "Fixacao na camera com confianca reduzida.")

        return PostCaptureFarDNPResult(rightDNPFar: correctedRight,
                                       leftDNPFar: correctedLeft,
                                       confidence: eyeGeometry.fixationConfidence,
                                       confidenceReason: confidenceReason)
    }

    // MARK: - Conversao geometrica
    /// Mede a DNP geometrica de perto assumindo fixacao no ponto da camera.
    private static func nearGeometricDNP(using eyeGeometry: CaptureEyeGeometrySnapshot) -> (right: Double, left: Double)? {
        let leftEyeCenter = eyeGeometry.leftEye.centerCamera.simdValue
        let rightEyeCenter = eyeGeometry.rightEye.centerCamera.simdValue

        return geometricDNP(using: eyeGeometry,
                            leftDirection: -leftEyeCenter,
                            rightDirection: -rightEyeCenter)
    }

    /// Mede a DNP geometrica em condicao de longe removendo a convergencia e mantendo os eixos paralelos.
    private static func farGeometricDNP(using eyeGeometry: CaptureEyeGeometrySnapshot) -> (right: Double, left: Double)? {
        let leftEyeCenter = eyeGeometry.leftEye.centerCamera.simdValue
        let rightEyeCenter = eyeGeometry.rightEye.centerCamera.simdValue
        let eyeMidpoint = (leftEyeCenter + rightEyeCenter) * 0.5

        guard let parallelDirection = normalized(-eyeMidpoint) else { return nil }

        return geometricDNP(using: eyeGeometry,
                            leftDirection: parallelDirection,
                            rightDirection: parallelDirection)
    }

    /// Mede as DNPs geometricas no plano do PC usando os vetores indicados.
    private static func geometricDNP(using eyeGeometry: CaptureEyeGeometrySnapshot,
                                     leftDirection: SIMD3<Float>,
                                     rightDirection: SIMD3<Float>) -> (right: Double, left: Double)? {
        let planePoint = eyeGeometry.pcCameraPosition.simdValue
        let leftEyeCenter = eyeGeometry.leftEye.centerCamera.simdValue
        let rightEyeCenter = eyeGeometry.rightEye.centerCamera.simdValue

        guard let leftIntersection = intersectionWithPCPlane(from: leftEyeCenter,
                                                             direction: leftDirection,
                                                             planePoint: planePoint),
              let rightIntersection = intersectionWithPCPlane(from: rightEyeCenter,
                                                              direction: rightDirection,
                                                              planePoint: planePoint) else {
            return nil
        }

        let rightDNP = abs(Double(rightIntersection.x - planePoint.x)) * 1000.0
        let leftDNP = abs(Double(leftIntersection.x - planePoint.x)) * 1000.0

        guard rightDNP.isFinite, leftDNP.isFinite else { return nil }
        return (right: rightDNP, left: leftDNP)
    }

    /// Intercepta a linha visual com o plano do PC, que e paralelo ao plano da imagem.
    private static func intersectionWithPCPlane(from eyeCenter: SIMD3<Float>,
                                                direction: SIMD3<Float>,
                                                planePoint: SIMD3<Float>) -> SIMD3<Float>? {
        guard let normalizedDirection = normalized(direction),
              abs(normalizedDirection.z) >= Constants.minimumPlaneDirectionZ else {
            return nil
        }

        let t = (planePoint.z - eyeCenter.z) / normalizedDirection.z
        guard t.isFinite, t >= 0 else { return nil }
        return eyeCenter + (normalizedDirection * t)
    }

    // MARK: - Helpers
    /// Estima um delta total usando apenas a profundidade real do PC e a posicao dos olhos.
    private static func fallbackGeometricDelta(using eyeGeometry: CaptureEyeGeometrySnapshot) -> Double {
        let leftEyeCenter = eyeGeometry.leftEye.centerCamera.simdValue
        let rightEyeCenter = eyeGeometry.rightEye.centerCamera.simdValue
        let planePoint = eyeGeometry.pcCameraPosition.simdValue
        let meanEyeCenter = (leftEyeCenter + rightEyeCenter) * 0.5

        let fixationDistance = max(Double(simd_length(meanEyeCenter)) * 1000.0, 1)
        let planeAdvance = abs(Double(planePoint.z - meanEyeCenter.z)) * 1000.0
        let interpupillaryDistance = abs(Double(rightEyeCenter.x - leftEyeCenter.x)) * 1000.0
        let estimated = interpupillaryDistance * (planeAdvance / fixationDistance)
        guard estimated.isFinite else { return 0 }
        return max(estimated, 0)
    }

    /// Normaliza um vetor retornando `nil` quando a magnitude for invalida.
    private static func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length.isFinite, length > .ulpOfOne else { return nil }
        return vector / length
    }

    /// Garante que a distribuicao do delta total continue estavel entre os olhos.
    private static func normalizedWeight(primary: Double,
                                         secondary: Double) -> Double {
        let positivePrimary = max(primary, 0)
        let positiveSecondary = max(secondary, 0)
        let total = positivePrimary + positiveSecondary

        guard total > 0 else { return 0.5 }

        let rawWeight = positivePrimary / total
        return min(max(rawWeight, Constants.minimumWeight),
                   1 - Constants.minimumWeight)
    }

    /// Mantem a medida final dentro da faixa clinica plausivel.
    private static func clampedDNP(_ value: Double) -> Double {
        min(max(value, Constants.minimumDNP), Constants.maximumDNP)
    }
}
