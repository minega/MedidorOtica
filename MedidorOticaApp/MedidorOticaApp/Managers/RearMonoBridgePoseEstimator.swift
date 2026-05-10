//
//  RearMonoBridgePoseEstimator.swift
//  MedidorOticaApp
//
//  Estima a pose do modo traseiro Mono sem usar LiDAR, Depth ou TrueDepth.
//

import CoreGraphics
import Foundation

// MARK: - Landmarks de pose Mono
/// Landmarks normalizados usados para validar os tres eixos no modo Mono.
struct RearMonoBridgePoseLandmarks {
    let imageLeftEyeCenter: NormalizedPoint?
    let imageRightEyeCenter: NormalizedPoint?
    let lowerNosePoint: NormalizedPoint?
    let lowerFacePoint: NormalizedPoint?
    let faceBounds: NormalizedRect
}

// MARK: - Estimativa por eixo
/// Estimativa interna de um eixo com confianca geometrica.
struct RearMonoBridgePoseAxisEstimate: Equatable {
    let degrees: Float
    let confidence: Float
}

// MARK: - Estimador de pose Mono
/// Resolve roll/yaw/pitch por geometria facial 2D e valida contra Vision quando disponivel.
enum RearMonoBridgePoseEstimator {
    private enum Constants {
        static let minimumAxisConfidence: Float = 0.70
        static let maximumPoseDegrees: Float = 45
        static let rollVisionAgreementDegrees: Float = 3.5
        static let yawVisionAgreementDegrees: Float = 5.0
        static let pitchVisionAgreementDegrees: Float = 5.0
        static let neutralEyeRelativeY: ClosedRange<Float> = 0.30...0.50
        static let neutralNoseDrop: ClosedRange<Float> = 0.14...0.32
        static let neutralLowerFaceDrop: ClosedRange<Float> = 0.42...0.70
        static let maximumPitchBoxBiasDegrees: Float = 5.5
        static let pitchDegreesPerRelativeUnit: Float = 34
        static let yawDegreesPerEyeShift: Float = 32
        static let neutralYawShift: Float = 0.025
    }

    /// Monta um snapshot somente quando roll, yaw e pitch possuem leitura geometrica confiavel.
    static func makeHeadPose(visionRoll: Float?,
                             visionYaw: Float?,
                             visionPitch: Float?,
                             landmarks: RearMonoBridgePoseLandmarks,
                             timestamp: TimeInterval) -> HeadPoseSnapshot? {
        let rollGeometry = rollFromEyes(landmarks)
        let yawGeometry = yawFromNoseAndEyes(landmarks)
        let pitchGeometry = pitchFromFaceProportions(landmarks)

        guard let roll = resolvedAxis(vision: visionRoll,
                                      geometry: rollGeometry,
                                      agreementTolerance: Constants.rollVisionAgreementDegrees),
              let yaw = resolvedAxis(vision: visionYaw,
                                     geometry: yawGeometry,
                                     agreementTolerance: Constants.yawVisionAgreementDegrees),
              let pitch = resolvedPitchAxis(vision: visionPitch,
                                            geometry: pitchGeometry) else {
            return nil
        }

        let snapshot = HeadPoseSnapshot(rollDegrees: roll,
                                        yawDegrees: yaw,
                                        pitchDegrees: pitch,
                                        timestamp: timestamp,
                                        sensor: .rearMonoBridge)
        return snapshot.isValid ? snapshot : nil
    }

    /// Calcula roll pela linha dos olhos, que e o sinal 2D mais estavel para inclinacao lateral.
    static func rollFromEyes(_ landmarks: RearMonoBridgePoseLandmarks) -> RearMonoBridgePoseAxisEstimate? {
        guard let eyes = sortedEyes(from: landmarks),
              landmarks.faceBounds.width > 0 else {
            return nil
        }

        let eyeDistance = distance(from: eyes.left, to: eyes.right)
        let minimumDistance = max(landmarks.faceBounds.width * 0.22, 0.055)
        guard eyeDistance >= minimumDistance else { return nil }

        let dy = Double(eyes.right.y - eyes.left.y)
        let dx = Double(eyes.right.x - eyes.left.x)
        let degrees = clampedPoseDegrees(radiansToDegrees(Float(atan2(dy, dx))))
        let confidence = min(max(Float(eyeDistance / max(minimumDistance, 0.0001)), 0), 1) * 0.18 + 0.76
        return RearMonoBridgePoseAxisEstimate(degrees: degrees,
                                              confidence: min(confidence, 0.96))
    }

    /// Estima yaw pelo deslocamento do dorso nasal em relacao ao centro dos olhos.
    static func yawFromNoseAndEyes(_ landmarks: RearMonoBridgePoseLandmarks) -> RearMonoBridgePoseAxisEstimate? {
        guard let eyes = sortedEyes(from: landmarks),
              let lowerNose = landmarks.lowerNosePoint,
              landmarks.faceBounds.width > 0,
              landmarks.faceBounds.height > 0 else {
            return nil
        }

        let eyeDistance = distance(from: eyes.left, to: eyes.right)
        let minimumDistance = max(landmarks.faceBounds.width * 0.22, 0.055)
        guard eyeDistance >= minimumDistance else { return nil }

        let eyeMidX = (eyes.left.x + eyes.right.x) * 0.5
        let eyeMidY = (eyes.left.y + eyes.right.y) * 0.5
        let noseDrop = (lowerNose.y - eyeMidY) / landmarks.faceBounds.height
        guard noseDrop >= 0.08, noseDrop <= 0.48 else { return nil }

        let normalizedShift = Float((lowerNose.x - eyeMidX) / max(eyeDistance, 0.0001))
        let effectiveShift: Float
        if abs(normalizedShift) <= Constants.neutralYawShift {
            effectiveShift = 0
        } else {
            effectiveShift = normalizedShift > 0 ?
                normalizedShift - Constants.neutralYawShift :
                normalizedShift + Constants.neutralYawShift
        }
        let degrees = clampedPoseDegrees(effectiveShift * Constants.yawDegreesPerEyeShift)
        let distanceScore = min(max(Float(eyeDistance / max(minimumDistance, 0.0001)), 0), 1)
        let noseScore = 1 - min(abs(Float(noseDrop - 0.22)) / 0.22, 1)
        let confidence = 0.72 + (distanceScore * 0.12) + (noseScore * 0.10)
        return RearMonoBridgePoseAxisEstimate(degrees: degrees,
                                              confidence: min(confidence, 0.94))
    }

    /// Estima pitch pela posicao vertical dos olhos dentro do rosto, validada por nariz/queixo.
    static func pitchFromFaceProportions(_ landmarks: RearMonoBridgePoseLandmarks) -> RearMonoBridgePoseAxisEstimate? {
        guard let eyes = sortedEyes(from: landmarks),
              landmarks.faceBounds.height > 0,
              landmarks.lowerNosePoint != nil || landmarks.lowerFacePoint != nil else {
            return nil
        }

        let eyeY = (eyes.left.y + eyes.right.y) * 0.5
        let relativeEyeY = Float((eyeY - landmarks.faceBounds.y) / landmarks.faceBounds.height)
        guard relativeEyeY >= 0.26, relativeEyeY <= 0.58 else { return nil }

        var confidence: Float = 0.70
        var noseDrop: Float?
        var lowerFaceDrop: Float?
        if let lowerNose = landmarks.lowerNosePoint {
            noseDrop = Float((lowerNose.y - eyeY) / landmarks.faceBounds.height)
            guard let noseDrop,
                  noseDrop >= 0.08,
                  noseDrop <= 0.48 else { return nil }
            confidence += 0.10
        }

        if let lowerFace = landmarks.lowerFacePoint {
            lowerFaceDrop = Float((lowerFace.y - eyeY) / landmarks.faceBounds.height)
            guard let lowerFaceDrop,
                  lowerFaceDrop >= 0.25,
                  lowerFaceDrop <= 0.74 else { return nil }
            confidence += 0.08
        }

        if pitchLooksNeutral(relativeEyeY: relativeEyeY,
                             noseDrop: noseDrop,
                             lowerFaceDrop: lowerFaceDrop) {
            return RearMonoBridgePoseAxisEstimate(degrees: 0,
                                                  confidence: min(confidence, 0.94))
        }

        let effectiveRelativeY: Float
        if Constants.neutralEyeRelativeY.contains(relativeEyeY) {
            effectiveRelativeY = 0
        } else if relativeEyeY < Constants.neutralEyeRelativeY.lowerBound {
            effectiveRelativeY = relativeEyeY - Constants.neutralEyeRelativeY.lowerBound
        } else {
            effectiveRelativeY = relativeEyeY - Constants.neutralEyeRelativeY.upperBound
        }
        let degrees = clampedPoseDegrees(effectiveRelativeY * Constants.pitchDegreesPerRelativeUnit)
        return RearMonoBridgePoseAxisEstimate(degrees: degrees,
                                              confidence: min(confidence, 0.94))
    }

    /// Trata o viés normal do retângulo facial como neutro quando nariz e queixo estão proporcionais.
    private static func pitchLooksNeutral(relativeEyeY: Float,
                                          noseDrop: Float?,
                                          lowerFaceDrop: Float?) -> Bool {
        guard Constants.neutralEyeRelativeY.contains(relativeEyeY) else { return false }

        let noseIsNeutral = noseDrop.map { Constants.neutralNoseDrop.contains($0) } ?? true
        let lowerFaceIsNeutral = lowerFaceDrop.map { Constants.neutralLowerFaceDrop.contains($0) } ?? true
        return noseIsNeutral && lowerFaceIsNeutral
    }

    /// Exige geometria confiavel; Vision apenas refina ou bloqueia de forma conservadora.
    static func resolvedAxis(vision: Float?,
                             geometry: RearMonoBridgePoseAxisEstimate?,
                             agreementTolerance: Float) -> Float? {
        guard let geometry,
              geometry.confidence >= Constants.minimumAxisConfidence,
              geometry.degrees.isFinite else {
            return nil
        }

        let geometricDegrees = clampedPoseDegrees(geometry.degrees)
        guard let vision,
              vision.isFinite else {
            return geometricDegrees
        }

        let visionDegrees = clampedPoseDegrees(vision)
        let disagreement = abs(visionDegrees - geometricDegrees)
        if disagreement <= agreementTolerance {
            return clampedPoseDegrees((visionDegrees * 0.55) + (geometricDegrees * 0.45))
        }

        // Em conflito, usa o maior erro absoluto para nao liberar captura por um eixo otimista.
        return abs(visionDegrees) >= abs(geometricDegrees) ? visionDegrees : geometricDegrees
    }

    /// O pitch 2D sofre viés do bounding box; Vision alinhado não deve ser vencido por erro pequeno e fixo.
    static func resolvedPitchAxis(vision: Float?,
                                  geometry: RearMonoBridgePoseAxisEstimate?) -> Float? {
        guard let geometry,
              geometry.confidence >= Constants.minimumAxisConfidence,
              geometry.degrees.isFinite else {
            return nil
        }

        let geometricDegrees = clampedPoseDegrees(geometry.degrees)
        guard let vision,
              vision.isFinite else {
            return geometricDegrees
        }

        let visionDegrees = clampedPoseDegrees(vision)
        let disagreement = abs(visionDegrees - geometricDegrees)
        if disagreement <= Constants.pitchVisionAgreementDegrees {
            return clampedPoseDegrees((visionDegrees * 0.65) + (geometricDegrees * 0.35))
        }

        if abs(visionDegrees) <= RearMonoBridgeCapturePrecisionPolicy.pitchToleranceDegrees,
           abs(geometricDegrees) <= Constants.maximumPitchBoxBiasDegrees {
            return visionDegrees
        }

        return abs(visionDegrees) >= abs(geometricDegrees) ? visionDegrees : geometricDegrees
    }

    // MARK: - Helpers
    private static func sortedEyes(from landmarks: RearMonoBridgePoseLandmarks) -> (left: NormalizedPoint, right: NormalizedPoint)? {
        guard let first = landmarks.imageLeftEyeCenter,
              let second = landmarks.imageRightEyeCenter else {
            return nil
        }

        return first.x <= second.x ? (first, second) : (second, first)
    }

    private static func distance(from first: NormalizedPoint,
                                 to second: NormalizedPoint) -> CGFloat {
        let dx = second.x - first.x
        let dy = second.y - first.y
        return sqrt((dx * dx) + (dy * dy))
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * (180 / .pi)
    }

    private static func clampedPoseDegrees(_ degrees: Float) -> Float {
        guard degrees.isFinite else { return 0 }
        return min(max(degrees, -Constants.maximumPoseDegrees),
                   Constants.maximumPoseDegrees)
    }
}
