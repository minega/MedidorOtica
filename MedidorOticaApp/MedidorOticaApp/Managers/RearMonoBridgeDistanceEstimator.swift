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

        if let cameraIntrinsics,
           let focalPixels = orientedHorizontalFocalPixels(from: cameraIntrinsics,
                                                           orientation: orientation),
           imageSize.width > 0 {
            let eyePixels = eyeDistanceRatio * Float(imageSize.width)
            guard eyePixels > 0 else { return nil }
            return clampedDistance((Constants.nominalPupilDistanceCm * focalPixels) / eyePixels)
        }

        return clampedDistance(Constants.eyeDistanceProductCm / eyeDistanceRatio)
    }

    private static func orientedHorizontalFocalPixels(from intrinsics: simd_float3x3,
                                                     orientation: CGImagePropertyOrientation) -> Float? {
        let focal = orientation.isPortrait ?
            intrinsics.columns.1.y :
            intrinsics.columns.0.x
        return focal.isFinite && focal > 0 ? focal : nil
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
