//
//  VisionGeometryHelper.swift
//  MedidorOticaApp
//
//  Funções utilitárias reutilizáveis para converter coordenadas retornadas pelo Vision.
//

import CoreGraphics
import Vision
import UIKit

// MARK: - Auxiliar de Geometria para Vision
enum VisionGeometryHelper {
    /// Retorna as dimensões orientadas para um buffer de pixels considerando a orientação informada.
    static func orientedDimensions(for buffer: CVPixelBuffer,
                                   orientation: CGImagePropertyOrientation) -> (width: Int, height: Int) {
        let rawWidth = CVPixelBufferGetWidth(buffer)
        let rawHeight = CVPixelBufferGetHeight(buffer)
        return orientation.isPortrait ? (rawHeight, rawWidth) : (rawWidth, rawHeight)
    }

    /// Versão equivalente para imagens `CGImage`.
    static func orientedDimensions(for image: CGImage,
                                   orientation: CGImagePropertyOrientation) -> (width: Int, height: Int) {
        let rawWidth = image.width
        let rawHeight = image.height
        return orientation.isPortrait ? (rawHeight, rawWidth) : (rawWidth, rawHeight)
    }

    /// Converte um ponto de pixel em coordenadas normalizadas (0...1) ajustando espelhamento.
    static func normalizedPoint(_ pixelPoint: CGPoint,
                                width: Int,
                                height: Int,
                                orientation: CGImagePropertyOrientation) -> CGPoint {
        guard width > 0, height > 0 else { return .zero }
        var point = CGPoint(x: pixelPoint.x / CGFloat(width),
                            y: pixelPoint.y / CGFloat(height))
        point.y = 1 - point.y
        if orientation.isMirrored { point.x = 1 - point.x }
        return clampedNormalizedPoint(point)
    }

    /// Garante que o ponto permaneça dentro do intervalo permitido.
    static func clampedNormalizedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1),
                y: min(max(point.y, 0), 1))
    }

    /// Calcula o centro médio de uma região de landmarks e converte para coordenadas normalizadas.
    static func normalizedPoint(from region: VNFaceLandmarkRegion2D,
                                boundingBox: CGRect,
                                imageWidth: Int,
                                imageHeight: Int,
                                orientation: CGImagePropertyOrientation) -> CGPoint? {
        guard region.pointCount > 0 else { return nil }

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for index in 0..<region.pointCount {
            let point = region.normalizedPoints[index]
            sumX += point.x
            sumY += point.y
        }

        let average = CGPoint(x: sumX / CGFloat(region.pointCount),
                               y: sumY / CGFloat(region.pointCount))
        let normalizedX = boundingBox.origin.x + average.x * boundingBox.width
        let normalizedY = boundingBox.origin.y + average.y * boundingBox.height

        let pixelPoint = VNImagePointForNormalizedPoint(CGPoint(x: normalizedX, y: normalizedY),
                                                        imageWidth,
                                                        imageHeight)
        return normalizedPoint(pixelPoint,
                               width: imageWidth,
                               height: imageHeight,
                               orientation: orientation)
    }

    /// Cria uma requisição de landmarks utilizando a revisão mais atual.
    static func makeLandmarksRequest() -> VNDetectFaceLandmarksRequest {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
    }
}
