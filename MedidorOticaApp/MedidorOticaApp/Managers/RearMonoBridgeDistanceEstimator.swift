//
//  RearMonoBridgeDistanceEstimator.swift
//  MedidorOticaApp
//
//  Estima a distância visual do modo traseiro Mono sem usar sensores de profundidade.
//

import CoreGraphics
import Foundation
import ImageIO
import simd

// MARK: - Estimador de distância Mono
/// Calcula uma distância aproximada para guiar a captura com a câmera traseira principal.
enum RearMonoBridgeDistanceEstimator {
    private enum Constants {
        /// Produto calibrado a partir dos testes reais: faceHeight 0,345 deve indicar perto de 25 cm.
        static let faceHeightDistanceProductCm: Float = 8.65
        /// Distância pupilar média usada quando a câmera entrega intrinsics.
        static let nominalPupilDistanceCm: Float = 6.3
        /// Produto conservador quando os intrinsics não estão disponíveis.
        static let eyeDistanceProductCm: Float = 5.7
        static let minimumUsableDistanceCm: Float = 15
        static let maximumUsableDistanceCm: Float = 90
    }

    /// Estima a distância combinando tamanho da face, distância dos olhos e intrinsics quando disponíveis.
    static func estimate(faceHeightRatio: Float,
                         eyeDistanceRatio: Float?,
                         imageSize: CGSize,
                         orientation: CGImagePropertyOrientation,
                         cameraIntrinsics: simd_float3x3?) -> Float {
        let faceEstimate = distanceFromFaceHeight(faceHeightRatio)
        let eyeEstimate = distanceFromEyes(eyeDistanceRatio: eyeDistanceRatio,
                                           imageSize: imageSize,
                                           orientation: orientation,
                                           cameraIntrinsics: cameraIntrinsics)
        let candidates = [faceEstimate, eyeEstimate].compactMap { $0 }
        guard !candidates.isEmpty else { return 0 }

        if candidates.count == 1 {
            return candidates[0]
        }

        // A face calibrada corrige o erro observado; os olhos estabilizam variações do retângulo facial.
        return (candidates[0] * 0.62) + (candidates[1] * 0.38)
    }

    /// Estimativa calibrada pelo tamanho vertical da face no frame.
    static func distanceFromFaceHeight(_ faceHeightRatio: Float) -> Float? {
        guard faceHeightRatio.isFinite,
              faceHeightRatio > 0 else {
            return nil
        }

        return clampedDistance(Constants.faceHeightDistanceProductCm / faceHeightRatio)
    }

    /// Estimativa por olhos, priorizando intrinsics reais da câmera quando o frame fornece.
    static func distanceFromEyes(eyeDistanceRatio: Float?,
                                 imageSize: CGSize,
                                 orientation: CGImagePropertyOrientation,
                                 cameraIntrinsics: simd_float3x3?) -> Float? {
        guard let eyeDistanceRatio,
              eyeDistanceRatio.isFinite,
              eyeDistanceRatio > 0 else {
            return nil
        }

        if cameraIntrinsics != nil,
           let focalPixels = RearMonoBridgeProjectionEstimator
            .orientedFocalPixels(from: cameraIntrinsics,
                                 imageSize: imageSize,
                                 orientation: orientation)?.fx,
           imageSize.width > 0 {
            let eyePixels = eyeDistanceRatio * Float(imageSize.width)
            guard eyePixels > 0 else { return nil }
            return clampedDistance((Constants.nominalPupilDistanceCm * focalPixels) / eyePixels)
        }

        return clampedDistance(Constants.eyeDistanceProductCm / eyeDistanceRatio)
    }

    private static func clampedDistance(_ distance: Float) -> Float? {
        guard distance.isFinite,
              distance >= Constants.minimumUsableDistanceCm,
              distance <= Constants.maximumUsableDistanceCm else {
            return nil
        }
        return distance
    }
}

// MARK: - Projecao Mono
/// Converte deslocamentos normalizados do preview em centimetros estimados.
enum RearMonoBridgeProjectionEstimator {
    private enum Constants {
        /// Aproximacao conservadora para a camera wide quando o frame ainda nao entregou intrinsics.
        static let fallbackFocalLengthRatio: Float = 0.82
    }

    /// Converte o erro visual do PC em deslocamento fisico estimado no plano do rosto.
    static func offsetCentimeters(normalizedOffset: SIMD2<Float>,
                                  imageSize: CGSize,
                                  orientation: CGImagePropertyOrientation,
                                  cameraIntrinsics: simd_float3x3?,
                                  distanceCm: Float) -> SIMD2<Float> {
        guard distanceCm.isFinite,
              distanceCm > 0,
              imageSize.width > 0,
              imageSize.height > 0,
              let focal = orientedFocalPixels(from: cameraIntrinsics,
                                              imageSize: imageSize,
                                              orientation: orientation) else {
            return .zero
        }

        let xPixels = normalizedOffset.x * Float(imageSize.width)
        let yPixels = normalizedOffset.y * Float(imageSize.height)
        let xCentimeters = (xPixels / focal.fx) * distanceCm
        let yCentimeters = (yPixels / focal.fy) * distanceCm
        return SIMD2<Float>(xCentimeters, yCentimeters)
    }

    /// Retorna as distancias focais ja orientadas para o preview atual.
    static func orientedFocalPixels(from intrinsics: simd_float3x3?,
                                    imageSize: CGSize,
                                    orientation: CGImagePropertyOrientation) -> (fx: Float, fy: Float)? {
        if let intrinsics {
            let rawFX = intrinsics.columns.0.x
            let rawFY = intrinsics.columns.1.y
            let fx = orientation.isPortrait ? rawFY : rawFX
            let fy = orientation.isPortrait ? rawFX : rawFY

            if fx.isFinite, fy.isFinite, fx > 0, fy > 0 {
                return (fx, fy)
            }
        }

        guard imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }

        let fallback = Float(max(imageSize.width, imageSize.height)) * Constants.fallbackFocalLengthRatio
        return fallback.isFinite && fallback > 0 ? (fallback, fallback) : nil
    }
}
