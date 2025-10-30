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

    /// Converte todos os pontos de uma região de landmarks para coordenadas normalizadas, respeitando a orientação da imagem.
    static func normalizedPoints(from region: VNFaceLandmarkRegion2D?,
                                 boundingBox: CGRect,
                                 imageWidth: Int,
                                 imageHeight: Int,
                                 orientation: CGImagePropertyOrientation) -> [CGPoint] {
        guard let region, region.pointCount > 0 else { return [] }

        var points: [CGPoint] = []
        points.reserveCapacity(Int(region.pointCount))

        for index in 0..<region.pointCount {
            let normalized = region.normalizedPoints[index]
            let translatedX = boundingBox.origin.x + normalized.x * boundingBox.width
            let translatedY = boundingBox.origin.y + normalized.y * boundingBox.height
            let pixelPoint = VNImagePointForNormalizedPoint(CGPoint(x: translatedX, y: translatedY),
                                                            imageWidth,
                                                            imageHeight)
            let converted = normalizedPoint(pixelPoint,
                                            width: imageWidth,
                                            height: imageHeight,
                                            orientation: orientation)
            points.append(converted)
        }

        return points
    }

    /// Converte uma bounding box do Vision para um retângulo normalizado alinhado ao preview.
    static func normalizedRect(from boundingBox: CGRect,
                                imageWidth: Int,
                                imageHeight: Int,
                                orientation: CGImagePropertyOrientation) -> NormalizedRect {
        let pixelRect = VNImageRectForNormalizedRect(boundingBox,
                                                     imageWidth,
                                                     imageHeight)
        let topLeft = normalizedPoint(CGPoint(x: pixelRect.minX, y: pixelRect.minY),
                                      width: imageWidth,
                                      height: imageHeight,
                                      orientation: orientation)
        let bottomRight = normalizedPoint(CGPoint(x: pixelRect.maxX, y: pixelRect.maxY),
                                          width: imageWidth,
                                          height: imageHeight,
                                          orientation: orientation)
        let originX = min(topLeft.x, bottomRight.x)
        let originY = min(topLeft.y, bottomRight.y)
        let width = abs(bottomRight.x - topLeft.x)
        let height = abs(bottomRight.y - topLeft.y)
        return NormalizedRect(x: originX,
                              y: originY,
                              width: width,
                              height: height).clamped()
    }

    /// Cria uma requisição de landmarks utilizando a revisão mais atual.
    static func makeLandmarksRequest() -> VNDetectFaceLandmarksRequest {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
    }
}
