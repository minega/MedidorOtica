//
//  PostCaptureFarDNPResolver.swift
//  MedidorOticaApp
//
//  Converte DNP perto em DNP longe usando a geometria ocular 3D da mesma captura.
//

import Foundation
import simd

// MARK: - Resultado da DNP longe
/// Resultado consolidado da conversão geométrica de DNP perto para longe.
struct PostCaptureFarDNPResult: Equatable {
    let rightDNPFar: Double
    let leftDNPFar: Double
    let confidence: Double
    let confidenceReason: String?
}

// MARK: - Resolver da DNP longe
/// Recalcula a DNP de longe removendo a componente convergente de perto da mesma captura.
struct PostCaptureFarDNPResolver {
    private enum Constants {
        /// Evita divisão por zero ao interceptar o plano do PC.
        static let minimumPlaneDirectionZ: Float = 0.02
        /// Mantém a conversão dentro de um intervalo óptico plausível por olho.
        static let minimumDNP: Double = 10
        static let maximumDNP: Double = 45
        /// Peso mínimo para não perder completamente um lado em situações assimétricas.
        static let minimumWeight = 0.2
    }

    /// Resolve a DNP de longe usando a mesma captura e sem tabela fixa.
    static func resolve(rightDNPNear: Double,
                        leftDNPNear: Double,
                        eyeGeometry: CaptureEyeGeometrySnapshot?) -> PostCaptureFarDNPResult {
        guard let eyeGeometry else {
            return PostCaptureFarDNPResult(rightDNPFar: rightDNPNear,
                                           leftDNPFar: leftDNPNear,
                                           confidence: 0,
                                           confidenceReason: "Geometria ocular 3D indisponível nesta captura.")
        }

        guard let currentNear = currentGeometricDNP(using: eyeGeometry),
              let currentFar = farGeometricDNP(using: eyeGeometry) else {
            return PostCaptureFarDNPResult(rightDNPFar: rightDNPNear,
                                           leftDNPFar: leftDNPNear,
                                           confidence: eyeGeometry.fixationConfidence,
                                           confidenceReason: "Não foi possível reconstruir a vergência com confiança.")
        }

        let rawRightDelta = currentFar.right - currentNear.right
        let rawLeftDelta = currentFar.left - currentNear.left
        let rawTotalDelta = rawRightDelta + rawLeftDelta
        let appliedTotalDelta = max(rawTotalDelta, 0)
        let rightWeight = normalizedWeight(primary: rawRightDelta,
                                           secondary: rawLeftDelta)
        let leftWeight = 1 - rightWeight

        let correctedRight = clampedDNP(rightDNPNear + (appliedTotalDelta * rightWeight))
        let correctedLeft = clampedDNP(leftDNPNear + (appliedTotalDelta * leftWeight))

        let confidenceReason = eyeGeometry.isFixationReliable ? nil :
            (eyeGeometry.fixationConfidenceReason ?? "Fixação na câmera com confiança reduzida.")

        return PostCaptureFarDNPResult(rightDNPFar: correctedRight,
                                       leftDNPFar: correctedLeft,
                                       confidence: eyeGeometry.fixationConfidence,
                                       confidenceReason: confidenceReason)
    }

    // MARK: - Conversão geométrica
    /// Mede a DNP geométrica atual pela interseção da linha de visão com o plano do PC.
    private static func currentGeometricDNP(using eyeGeometry: CaptureEyeGeometrySnapshot) -> (right: Double, left: Double)? {
        geometricDNP(using: eyeGeometry,
                     leftDirection: eyeGeometry.leftEye.gazeCamera.simdValue,
                     rightDirection: eyeGeometry.rightEye.gazeCamera.simdValue)
    }

    /// Mede a DNP geométrica em condição de longe removendo apenas a convergência.
    private static func farGeometricDNP(using eyeGeometry: CaptureEyeGeometrySnapshot) -> (right: Double, left: Double)? {
        let averageDirection = normalized(eyeGeometry.leftEye.gazeCamera.simdValue +
                                          eyeGeometry.rightEye.gazeCamera.simdValue)
        guard let averageDirection else { return nil }

        return geometricDNP(using: eyeGeometry,
                            leftDirection: averageDirection,
                            rightDirection: averageDirection)
    }

    /// Mede as DNPs geométricas no plano do PC usando os vetores indicados.
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

    /// Intercepta a linha visual com o plano do PC, que é paralelo ao plano da imagem.
    private static func intersectionWithPCPlane(from eyeCenter: SIMD3<Float>,
                                                direction: SIMD3<Float>,
                                                planePoint: SIMD3<Float>) -> SIMD3<Float>? {
        guard let normalizedDirection = normalized(direction),
              abs(normalizedDirection.z) >= Constants.minimumPlaneDirectionZ else {
            return nil
        }

        let t = (planePoint.z - eyeCenter.z) / normalizedDirection.z
        guard t.isFinite else { return nil }
        return eyeCenter + (normalizedDirection * t)
    }

    // MARK: - Helpers
    /// Normaliza um vetor retornando `nil` quando a magnitude for inválida.
    private static func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length.isFinite, length > .ulpOfOne else { return nil }
        return vector / length
    }

    /// Garante que a distribuição do delta total continue estável entre os olhos.
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

    /// Mantém a medida final dentro da faixa clínica plausível.
    private static func clampedDNP(_ value: Double) -> Double {
        min(max(value, Constants.minimumDNP), Constants.maximumDNP)
    }
}
